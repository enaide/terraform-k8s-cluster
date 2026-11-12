#!/bin/bash
set -euo pipefail

NODE_ROLE="${NODE_ROLE}"
LOG_DIR="/var/log/k8s-init"
GLOBAL_LOG="$LOG_DIR/init.log"
SCRIPT_DIR="/opt/k8s-scripts"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$GLOBAL_LOG") 2>&1

echo "======================================================"
echo "INICIO: $(date) | Nodo: $(hostname -s) | Rol: $NODE_ROLE"
echo "======================================================"

run_phase() {
  local PHASE_NAME="$1"
  local SCRIPT_PATH="$2"
  local PHASE_LOG="$LOG_DIR/$PHASE_NAME.log"

  echo ""
  echo ">>> FASE: $PHASE_NAME — $(date)"
  set +e
  bash "$SCRIPT_PATH" 2>&1 | tee "$PHASE_LOG"
  EXIT_CODE="${PIPESTATUS[0]}"
  set -e

  if [ "$EXIT_CODE" -eq 0 ]; then
    echo "<<< $PHASE_NAME OK"
  else
    echo "<<< $PHASE_NAME FALLIDA (exit $EXIT_CODE) ❌"
    exit "$EXIT_CODE"
  fi
}

run_phase "01-swap"           "$SCRIPT_DIR/common/01-swap.sh"
run_phase "02-kernel-modules" "$SCRIPT_DIR/common/02-kernel-modules.sh"
run_phase "03-sysctl"         "$SCRIPT_DIR/common/03-sysctl.sh"
run_phase "04-containerd"     "$SCRIPT_DIR/common/04-containerd.sh"
run_phase "05-kubernetes"     "$SCRIPT_DIR/common/05-kubernetes.sh"

# ── Fase 06: ruta explícita según rol ─────────────────────────────
if [ "$NODE_ROLE" = "control-plane" ]; then
  run_phase "06-control-plane" "$SCRIPT_DIR/control-plane/06-kubeadm-init.sh"
elif [ "$NODE_ROLE" = "worker" ]; then
  run_phase "06-worker"        "$SCRIPT_DIR/worker/06-kubeadm-join.sh"
else
  echo "ERROR: NODE_ROLE desconocido: '$NODE_ROLE'"
  exit 1
fi

echo ""
echo "======================================================"
echo "COMPLETADO: $(date) — todas las fases OK"
echo "======================================================"