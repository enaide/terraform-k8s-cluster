#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# wait-for-cluster.sh — Espera a que el clúster esté listo.
#
# Lo lanza wait.tf al final del apply, pero también puedes ejecutarlo a mano:
#
#   CP_IP=1.2.3.4 ENV_PREFIX=dev-k8s AWS_REGION=eu-south-2 AWS_PROFILE=dev \
#   SSH_KEY=~/.ssh/id_ed25519 EXPECTED_NODES=3 \
#   bash scripts/wait-for-cluster.sh
#
# Fases:
#   1. El control plane publica cp-ready=true en SSM
#   2. Hay acceso SSH al control plane
#   3. `kubectl get nodes` muestra EXPECTED_NODES nodos en estado Ready
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Entradas (variables de entorno) ──────────────────────────────────────────
# Obligatorias: el script se detiene con un mensaje claro si falta alguna.
: "${CP_IP:?Falta CP_IP (IP pública del control plane)}"
: "${ENV_PREFIX:?Falta ENV_PREFIX}"
: "${AWS_REGION:?Falta AWS_REGION}"
: "${EXPECTED_NODES:?Falta EXPECTED_NODES}"

# Opcionales, con valor por defecto
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_USER="${SSH_USER:-ec2-user}"
# AWS_PROFILE: si no se define, la AWS CLI usa su perfil por defecto.

# Reintentos por fase: número de intentos y segundos entre intentos
SSM_RETRIES="${SSM_RETRIES:-40}";     SSM_INTERVAL="${SSM_INTERVAL:-30}"
SSH_RETRIES="${SSH_RETRIES:-20}";     SSH_INTERVAL="${SSH_INTERVAL:-10}"
NODES_RETRIES="${NODES_RETRIES:-30}"; NODES_INTERVAL="${NODES_INTERVAL:-10}"

# Laboratorio: las instancias son nuevas en cada apply, así que no se
# comprueba ni se guarda su clave de host.
SSH_OPTS=(
  -i "$SSH_KEY"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=5
  -o BatchMode=yes
)

# ── Utilidades ───────────────────────────────────────────────────────────────

# Ejecuta un comando en el control plane por SSH
remote() {
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$CP_IP" "$@"
}

# retry <descripción> <intentos> <intervalo_s> <comando...>
# Repite <comando> hasta que devuelva 0 o se agoten los intentos.
retry() {
  local desc="$1" max="$2" interval="$3"
  shift 3

  local i
  for ((i = 1; i <= max; i++)); do
    if "$@"; then
      echo "  ✅ $desc (intento $i/$max)"
      return 0
    fi
    echo "  ⏳ $desc — intento $i/$max, reintento en ${interval}s"
    if ((i < max)); then
      sleep "$interval"
    fi
  done

  echo "  ❌ Timeout: $desc tras $((max * interval))s" >&2
  return 1
}

# ── Comprobaciones (una por fase) ────────────────────────────────────────────

cp_ready_in_ssm() {
  local value
  value=$(aws ssm get-parameter --name "/$ENV_PREFIX/cp-ready" --query "Parameter.Value" --output text 2>/dev/null || true)
  [[ "$value" == "true" ]]
}

ssh_available() {
  remote true 2>/dev/null
}

all_nodes_ready() {
  local ready
  # awk cuenta las filas cuya columna STATUS es exactamente "Ready";
  # devuelve 0 aunque no haya ninguna, a diferencia de `grep -c`.
  ready=$(remote "kubectl get nodes --no-headers 2>/dev/null | awk '\$2 == \"Ready\"' | wc -l" 2>/dev/null || echo 0)
  echo "     nodos Ready: $ready/$EXPECTED_NODES"
  ((ready >= EXPECTED_NODES))
}

# ── Ejecución ────────────────────────────────────────────────────────────────

echo "════════════════════════════════════════"
echo "  Clúster:         $ENV_PREFIX ($AWS_REGION)"
echo "  Control plane:   $CP_IP"
echo "  Nodos esperados: $EXPECTED_NODES"
echo "  Perfil AWS:      ${AWS_PROFILE:-<por defecto>}"
echo "════════════════════════════════════════"

echo; echo "▶ Fase 1/3 — Señal cp-ready en SSM"
retry "control plane listo" "$SSM_RETRIES" "$SSM_INTERVAL" cp_ready_in_ssm

echo; echo "▶ Fase 2/3 — SSH al control plane"
retry "SSH disponible" "$SSH_RETRIES" "$SSH_INTERVAL" ssh_available

echo; echo "▶ Fase 3/3 — Nodos en estado Ready"
retry "todos los nodos Ready" "$NODES_RETRIES" "$NODES_INTERVAL" all_nodes_ready

echo
echo "════════════════════════════════════════"
echo "  ✅ CLÚSTER LISTO"
echo "════════════════════════════════════════"
remote "kubectl get nodes -o wide"

echo
echo "Para gestionar el clúster:"
echo "  ssh -i $SSH_KEY $SSH_USER@$CP_IP"
echo "  kubectl get nodes"
