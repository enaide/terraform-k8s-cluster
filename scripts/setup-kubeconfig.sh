#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-kubeconfig.sh — Configura kubectl en tu PC para usar el clúster de AWS.
#
# Úsalo con `source` (desde bash o zsh) después de `terraform apply`:
#
#   source scripts/setup-kubeconfig.sh
#
# Qué hace:
#   1. Lee la IP pública del control plane de los outputs de Terraform
#   2. Descarga ~/.kube/config del control plane por SSH
#   3. Lo guarda en ~/.kube/<contexto>.conf (permisos 600) apuntando a la IP
#      pública y con el contexto renombrado
#   4. Comprueba el acceso con `kubectl get nodes`
#   5. Deja `export KUBECONFIG=~/.kube/config:~/.kube/<contexto>.conf` en
#      ~/.zshrc (bloque único, idempotente). Así conviven minikube y AWS.
#   6. Exporta KUBECONFIG en la terminal actual (solo si se cargó con source)
#      y activa el contexto <contexto>
#
# ~/.kube/config (minikube) nunca se reescribe: solo cambia su línea
# current-context al activar el contexto. Volver: kubectl config use-context minikube
#
# Variables opcionales:
#   K8S_CONTEXT  nombre del contexto y del archivo   (dev-k8s)
#   SSH_KEY      clave privada SSH                    ($HOME/.ssh/id_ed25519)
#   SSH_USER     usuario SSH del nodo                 (ec2-user)
#   RC_FILE      archivo de arranque de la shell      ($HOME/.zshrc)
#   NO_PERSIST   si vale 1, no modifica RC_FILE
#   TF_DIR       directorio del proyecto Terraform    (raíz del repositorio git)
#
# Importante: como se carga con `source`, se ejecuta dentro de TU shell.
# Por eso no usa `set -e` ni `exit` (cerrarían la terminal): toda la lógica
# va dentro de una función que corta con `return`.
# ─────────────────────────────────────────────────────────────────────────────

_setup_kubeconfig() {
  local context="${K8S_CONTEXT:-dev-k8s}"
  local ssh_key="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
  local ssh_user="${SSH_USER:-ec2-user}"
  local rc_file="${RC_FILE:-$HOME/.zshrc}"
  local tf_dir="${TF_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  local kube_dir="$HOME/.kube"
  local kcfg="$kube_dir/$context.conf"
  # ~/.kube/config va primero: minikube y kubectl escriben ahí, y este script
  # solo reescribe su propio archivo ($kcfg).
  local kcfg_list="$kube_dir/config:$kcfg"
  local begin_marker="# >>> setup-kubeconfig >>>"
  local end_marker="# <<< setup-kubeconfig <<<"
  local cp_ip tmp tool

  # Mismas opciones que wait-for-cluster.sh: las instancias son nuevas en cada
  # apply, así que no se comprueba ni se guarda su clave de host.
  local ssh_opts=(
    -i "$ssh_key"
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=5
    -o BatchMode=yes
  )

  # ── 1. Herramientas necesarias ─────────────────────────────────────────────
  # `command` ejecuta el binario real aunque exista un alias (p. ej. kubecolor).
  for tool in terraform ssh kubectl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "❌ No se encuentra '$tool' en el PATH" >&2
      return 1
    fi
  done
  if [[ ! -r "$ssh_key" ]]; then
    echo "❌ No se puede leer la clave SSH: $ssh_key" >&2
    return 1
  fi

  # ── 2. IP pública del control plane ────────────────────────────────────────
  echo "▶ Leyendo outputs de Terraform en $tf_dir"
  cp_ip=$(command terraform -chdir="$tf_dir" output -raw control_plane_public_ip 2>/dev/null)
  if [[ -z "$cp_ip" || "$cp_ip" == *"No outputs"* || "$cp_ip" == *"Warning"* ]]; then
    echo "❌ No hay output 'control_plane_public_ip': ¿hiciste terraform apply?" >&2
    return 1
  fi
  echo "  ✅ Control plane: $cp_ip"

  # ── 3. Descargar el kubeconfig ─────────────────────────────────────────────
  echo "▶ Descargando kubeconfig del control plane"
  mkdir -p "$kube_dir" || return 1
  tmp=$(mktemp "$kube_dir/.$context.conf.XXXXXX") || return 1
  chmod 600 "$tmp"
  if ! command ssh "${ssh_opts[@]}" "$ssh_user@$cp_ip" 'cat ~/.kube/config' >"$tmp" || [[ ! -s "$tmp" ]]; then
    echo "❌ No se pudo descargar ~/.kube/config de $ssh_user@$cp_ip" >&2
    rm -f "$tmp"
    return 1
  fi

  # ── 4. Nombres propios, IP pública y contexto ──────────────────────────────
  # kubeadm usa nombres genéricos (clúster "kubernetes", usuario
  # "kubernetes-admin"). Al combinarse con ~/.kube/config (minikube, etc.)
  # podrían chocar con otras entradas, así que se renombran a "$context".
  # Se edita el temporal: si algo falla, el archivo final anterior no se toca.
  sed -i \
    -e "s/^  name: kubernetes\$/  name: $context/" \
    -e "s/^    cluster: kubernetes\$/    cluster: $context/" \
    -e "s/^    user: kubernetes-admin\$/    user: $context/" \
    -e "s/^- name: kubernetes-admin\$/- name: $context/" \
    "$tmp"

  if ! command kubectl --kubeconfig "$tmp" config set-cluster "$context" \
         --server="https://$cp_ip:6443" >/dev/null ||
     ! command kubectl --kubeconfig "$tmp" config rename-context \
         kubernetes-admin@kubernetes "$context" >/dev/null ||
     ! command kubectl --kubeconfig "$tmp" config use-context "$context" >/dev/null; then
    echo "❌ No se pudo ajustar el kubeconfig descargado" >&2
    rm -f "$tmp"
    return 1
  fi

  # Comprobar que el renombrado funcionó (por si kubeadm cambia el formato)
  local names
  names=$(command kubectl --kubeconfig "$tmp" config view \
    -o jsonpath='{.clusters[*].name} {.users[*].name} {.contexts[*].name} {.contexts[0].context.cluster} {.contexts[0].context.user}')
  if [[ "$names" != "$context $context $context $context $context" ]]; then
    echo "❌ Formato de kubeconfig inesperado (nombres: $names)" >&2
    rm -f "$tmp"
    return 1
  fi

  mv -f "$tmp" "$kcfg" || { rm -f "$tmp"; return 1; }
  echo "  ✅ Guardado en $kcfg (clúster, usuario y contexto '$context')"

  # Si ~/.kube/config ya define el mismo nombre, esa entrada tiene prioridad
  # al combinar ambos archivos. Solo se avisa: tu archivo no se modifica.
  if [[ -f "$kube_dir/config" ]]; then
    local existing
    existing=$(command kubectl --kubeconfig "$kube_dir/config" config view \
      -o jsonpath='{.clusters[*].name} {.users[*].name} {.contexts[*].name}' 2>/dev/null)
    if [[ " $existing " == *" $context "* ]]; then
      echo "  ⚠️  ~/.kube/config ya tiene una entrada llamada '$context' y tiene prioridad." >&2
      echo "     Bórrala con: kubectl --kubeconfig ~/.kube/config config delete-context $context" >&2
      echo "                  (y delete-cluster / delete-user $context si existen)" >&2
    fi
  fi

  # ── 5. Comprobar el acceso ─────────────────────────────────────────────────
  echo "▶ Comprobando acceso al API server"
  if ! command kubectl --kubeconfig "$kcfg" --request-timeout=15s get nodes; then
    echo "  ⚠️  kubectl no responde; revisa la red o el puerto 6443 del security group." >&2
    echo "     El kubeconfig ya está guardado y se configura igualmente." >&2
  fi

  # ── 6. Persistir en el archivo de arranque de la shell ─────────────────────
  if [[ "${NO_PERSIST:-}" == "1" ]]; then
    echo "▶ NO_PERSIST=1: no se modifica $rc_file"
  else
    echo "▶ Guardando KUBECONFIG en $rc_file"
    touch "$rc_file" || return 1
    # Borra el bloque anterior (si existe) y añade el nuevo al final.
    sed -i "/^$begin_marker\$/,/^$end_marker\$/d" "$rc_file" || return 1
    printf '%s\nexport KUBECONFIG="%s"\n%s\n' "$begin_marker" "$kcfg_list" "$end_marker" >>"$rc_file"
    echo "  ✅ Las terminales nuevas verán ~/.kube/config y $kcfg"
  fi

  # ── 7. Aplicar en la terminal actual y activar el contexto ─────────────────
  # Con varios archivos, kubectl guarda los cambios (y minikube sus entradas)
  # en el PRIMERO: ~/.kube/config. Aquí solo cambia su línea current-context.
  export KUBECONFIG="$kcfg_list"
  command kubectl config use-context "$context" >/dev/null || return 1
  return 0
}

# ¿Se ha cargado con `source` o se ha ejecutado como programa?
if [[ -n "${ZSH_VERSION:-}" ]]; then
  [[ "${ZSH_EVAL_CONTEXT:-}" == *:file* ]] && _skc_sourced=1 || _skc_sourced=0
else
  [[ "${BASH_SOURCE[0]}" != "$0" ]] && _skc_sourced=1 || _skc_sourced=0
fi

if _setup_kubeconfig; then
  echo
  if [[ "$_skc_sourced" == "1" ]]; then
    echo "✅ KUBECONFIG=$KUBECONFIG aplicado en esta terminal"
    echo
    command kubectl config get-contexts
    echo
    echo "   Cambiar de clúster: kubectl config use-context <nombre>  (p. ej. minikube)"
  else
    echo "⚠️  Ejecutado sin 'source': KUBECONFIG no se aplicó a esta terminal."
    echo "   Usa 'source scripts/setup-kubeconfig.sh' o abre una terminal nueva."
  fi
  _skc_status=0
else
  echo "❌ Configuración de kubectl incompleta" >&2
  _skc_status=1
fi

# Limpieza: no dejar funciones ni variables auxiliares en tu shell.
unset -f _setup_kubeconfig
unset _skc_sourced
if [[ "${_skc_status}" == "1" ]]; then
  unset _skc_status
  # `return` si se cargó con source; `exit` solo si es un proceso propio.
  return 1 2>/dev/null || exit 1
fi
unset _skc_status
