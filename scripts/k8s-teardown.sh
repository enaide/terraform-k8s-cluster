#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# k8s-teardown.sh — Destruye lo que Terraform NO controla, sin dejar huérfanos.
#
# Los discos EBS de los PVC los crea el EBS CSI driver desde Kubernetes, no
# Terraform: `terraform destroy` no los conoce y quedarían cobrando.
#
# Orden obligatorio al terminar una sesión:
#   1. scripts/k8s-teardown.sh               (clúster vivo: limpia Kubernetes + barrido AWS)
#   2. terraform destroy
#   3. scripts/k8s-teardown.sh --sweep-only  (clúster destruido: barrido AWS final)
#
# Fases:
#   1. Kubernetes (si el contexto responde): desinstala las releases de Helm,
#      borra los PVC de discos EBS, espera a que el driver borre los discos y
#      desinstala el driver al final.
#   2. AWS (siempre): busca discos y snapshots con las etiquetas propias del
#      driver (Project=<ENV_PREFIX>, ManagedBy=aws-ebs-csi-driver) y borra los
#      que estén libres. Los discos raíz de Terraform no llevan esas etiquetas.
#
# Opciones:
#   --yes         no pide confirmación antes de borrar en AWS
#   --sweep-only  solo la fase 2 (para después de terraform destroy)
#
# Variables opcionales (por defecto):
#   K8S_CONTEXT (dev-k8s) · ENV_PREFIX (dev-k8s) · AWS_PROFILE (dev)
#   AWS_REGION (eu-south-2) · PV_WAIT_SECONDS (300)
#
# Código de salida: 0 si no queda nada; 1 si queda algo por limpiar.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

K8S_CONTEXT="${K8S_CONTEXT:-dev-k8s}"
ENV_PREFIX="${ENV_PREFIX:-dev-k8s}"
export AWS_PROFILE="${AWS_PROFILE:-dev}"
export AWS_REGION="${AWS_REGION:-eu-south-2}"
PV_WAIT_SECONDS="${PV_WAIT_SECONDS:-300}"

LAB_NS="lab"
INGRESS_NS="ingress-nginx"
CSI_NS="kube-system"
CSI_DRIVER="ebs.csi.aws.com"
TAG_MANAGED_BY="aws-ebs-csi-driver"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ASSUME_YES=0
SWEEP_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    --sweep-only) SWEEP_ONLY=1 ;;
    -h | --help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "❌ Opción desconocida: $arg (usa --help)" >&2; exit 2 ;;
  esac
done

# ── Utilidades ───────────────────────────────────────────────────────────────

# kubectl y helm SIEMPRE contra el contexto del laboratorio (nunca minikube).
k() { kubectl --context "$K8S_CONTEXT" --request-timeout=20s "$@"; }
h() { helm --kube-context "$K8S_CONTEXT" "$@"; }

confirm() {
  ((ASSUME_YES)) && return 0
  [[ -t 0 ]] || { echo "  (sin terminal interactiva: usa --yes para borrar)"; return 1; }
  local answer
  read -r -p "  $1 [s/N] " answer
  [[ "$answer" == [sS] ]]
}

for tool in aws kubectl helm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "❌ Falta '$tool' en el PATH" >&2; exit 2; }
done

# PVs del driver EBS: "pv namespace/pvc reclaimPolicy" por línea
ebs_pvs() {
  k get pv -o jsonpath="{range .items[?(@.spec.csi.driver==\"$CSI_DRIVER\")]}{.metadata.name}{\" \"}{.spec.claimRef.namespace}{\"/\"}{.spec.claimRef.name}{\" \"}{.spec.persistentVolumeReclaimPolicy}{\"\\n\"}{end}"
}

helm_uninstall() {
  local ns="$1" release="$2"
  if h status "$release" -n "$ns" >/dev/null 2>&1; then
    h uninstall "$release" -n "$ns" --wait --timeout 5m >/dev/null
    echo "  ✅ helm uninstall $release ($ns)"
  else
    echo "  · $release no está instalado"
  fi
}

# ── Fase 1: Kubernetes ───────────────────────────────────────────────────────

phase_kubernetes() {
  echo "▶ Fase 1/2 — Kubernetes (contexto $K8S_CONTEXT)"

  if ! kubectl config get-contexts "$K8S_CONTEXT" >/dev/null 2>&1 || ! k get --raw /readyz >/dev/null 2>&1; then
    echo "  ⚠️  El contexto '$K8S_CONTEXT' no responde."
    echo "     Si el clúster ya se destruyó es normal: se pasa al barrido de AWS."
    echo "     Si sigue vivo, ejecuta antes: source scripts/setup-kubeconfig.sh"
    return 0
  fi

  # 1. Aplicaciones (en orden inverso a la instalación)
  helm_uninstall "$LAB_NS" mongo-express
  helm_uninstall "$LAB_NS" mongodb
  helm_uninstall "$INGRESS_NS" ingress-nginx
  if k get namespace "$LAB_NS" >/dev/null 2>&1; then
    k delete -f "$REPO_ROOT/k8s/01-nginx-deployment/nginx.yaml" --ignore-not-found >/dev/null
    echo "  ✅ Deployment de prueba (nginx) eliminado"
  fi

  # 2. Services LoadBalancer: aquí no crean nada en AWS (no hay cloud
  #    provider), pero no deberían existir.
  local lbs
  lbs=$(k get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}')
  if [[ -n "$lbs" ]]; then
    echo "  ⚠️  Services de tipo LoadBalancer (bórralos tú si no los esperabas):"
    echo "$lbs" | sed 's/^/     - /'
  fi

  # 3. PVC: helm uninstall NO borra los PVC de un StatefulSet. Se borran todos
  #    los PVC ligados a discos EBS (en cualquier namespace) y los de "lab".
  local line pv claim policy
  while read -r pv claim policy; do
    [[ -z "$pv" ]] && continue
    k delete pvc -n "${claim%%/*}" "${claim##*/}" --ignore-not-found --wait=false >/dev/null
    echo "  ✅ PVC $claim borrado (PV $pv, reclaimPolicy $policy)"
  done < <(ebs_pvs)
  if k get namespace "$LAB_NS" >/dev/null 2>&1; then
    k delete pvc --all -n "$LAB_NS" --ignore-not-found --wait=false >/dev/null
  fi

  # 4. Esperar a que el driver borre los discos (necesita seguir instalado)
  local waited=0 remaining
  remaining=$(ebs_pvs | grep -c . || true)
  while ((remaining > 0 && waited < PV_WAIT_SECONDS)); do
    echo "  ⏳ PVs de EBS pendientes: $remaining (esperando ${waited}s/${PV_WAIT_SECONDS}s)"
    sleep 10
    waited=$((waited + 10))
    remaining=$(ebs_pvs | grep -c . || true)
  done

  # PVs con reclaimPolicy Retain: el driver no borra su disco. Se elimina el
  # objeto PV y el disco lo borra el barrido de AWS (fase 2).
  while read -r pv claim policy; do
    [[ -z "$pv" ]] && continue
    if [[ "$policy" == "Retain" ]]; then
      k delete pv "$pv" --ignore-not-found >/dev/null
      echo "  ⚠️  PV $pv (Retain) eliminado; su disco se borra en la fase 2"
    fi
  done < <(ebs_pvs)
  remaining=$(ebs_pvs | grep -c . || true)

  # 5. El driver se desinstala el último, solo si ya no quedan discos suyos
  if ((remaining == 0)); then
    echo "  ✅ Sin PVs de EBS"
    helm_uninstall "$CSI_NS" aws-ebs-csi-driver
  else
    echo "  ❌ Quedan $remaining PVs de EBS: NO se desinstala el driver." >&2
    ebs_pvs | sed 's/^/     - /' >&2
  fi

  # 6. Namespaces del laboratorio
  for ns in "$LAB_NS" "$INGRESS_NS"; do
    if k get namespace "$ns" >/dev/null 2>&1; then
      k delete namespace "$ns" --ignore-not-found --timeout=120s >/dev/null && echo "  ✅ Namespace $ns eliminado"
    fi
  done
}

# ── Fase 2: barrido de AWS ───────────────────────────────────────────────────

TAG_FILTERS=(
  "Name=tag:Project,Values=$ENV_PREFIX"
  "Name=tag:ManagedBy,Values=$TAG_MANAGED_BY"
)

list_volumes() {
  aws ec2 describe-volumes --filters "${TAG_FILTERS[@]}" \
    --query 'Volumes[].[VolumeId,State,Size]' --output text
}

list_snapshots() {
  aws ec2 describe-snapshots --owner-ids self --filters "${TAG_FILTERS[@]}" \
    --query 'Snapshots[].[SnapshotId,State]' --output text
}

phase_aws() {
  echo "▶ Fase 2/2 — Barrido de AWS ($AWS_PROFILE · $AWS_REGION · Project=$ENV_PREFIX)"

  local id state size vols snaps
  vols=$(list_volumes)
  if [[ -z "$vols" ]]; then
    echo "  ✅ Ningún disco EBS del driver"
  else
    while read -r id state size; do
      if [[ "$state" == "available" ]]; then
        echo "  · Disco huérfano $id (${size} GiB, $state)"
        if confirm "¿Borrar $id?"; then
          aws ec2 delete-volume --volume-id "$id"
          echo "  ✅ $id borrado"
        fi
      else
        echo "  ⚠️  Disco $id (${size} GiB) en estado '$state': sigue en uso."
        echo "     Repite el script con el clúster vivo (fase 1) o espera a que se libere."
      fi
    done <<<"$vols"
  fi

  snaps=$(list_snapshots)
  if [[ -z "$snaps" ]]; then
    echo "  ✅ Ningún snapshot del driver"
  else
    while read -r id state; do
      echo "  · Snapshot $id ($state)"
      if confirm "¿Borrar $id?"; then
        aws ec2 delete-snapshot --snapshot-id "$id"
        echo "  ✅ $id borrado"
      fi
    done <<<"$snaps"
  fi
}

# ── Ejecución ────────────────────────────────────────────────────────────────

echo "════════════════════════════════════════"
echo "  Limpieza fuera de Terraform — $ENV_PREFIX"
echo "════════════════════════════════════════"

if ((SWEEP_ONLY)); then
  echo "▶ Fase 1/2 — omitida (--sweep-only)"
else
  phase_kubernetes
fi
echo
phase_aws

# Comprobación final (deleted / deleting ya no cuentan)
left_vols=$(list_volumes | awk '$2 != "deleted" && $2 != "deleting"' | grep -c . || true)
left_snaps=$(list_snapshots | grep -c . || true)
echo
echo "════════════════════════════════════════"
if ((left_vols == 0 && left_snaps == 0)); then
  echo "  ✅ Nada pendiente en AWS fuera de Terraform"
  echo "════════════════════════════════════════"
  exit 0
fi
echo "  ❌ Quedan $left_vols discos y $left_snaps snapshots"
echo "════════════════════════════════════════"
exit 1
