#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# ORQUESTADOR: init.sh
# Ejecuta cada fase en orden con detección real de fallos.
# Si una fase falla, el orquestador para, indica qué falló
# y sale con exit 1 — cloud-init registra el fallo.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

NODE_ROLE="${node_role}"
LOG_DIR="/var/log/k8s-init"
GLOBAL_LOG="$LOG_DIR/init.log"
SCRIPT_DIR="/opt/k8s-scripts"

mkdir -p "$LOG_DIR" "$SCRIPT_DIR/common" "$SCRIPT_DIR/$NODE_ROLE"
exec > >(tee -a "$GLOBAL_LOG") 2>&1

echo "======================================================"
echo "INICIO: $(date)"
echo "Nodo:   $(hostname -s)"
echo "Rol:    $NODE_ROLE"
echo "======================================================"

# ── Función central: captura el exit code real del script ─────────
# CORRECCIÓN BUG 1: usar archivo temporal para capturar exit code
# en lugar de pipe a tee, que devuelve el exit code de tee (siempre 0)
run_phase() {
  local PHASE_NAME="$1"
  local SCRIPT_PATH="$2"
  local PHASE_LOG="$LOG_DIR/$PHASE_NAME.log"
  local EXIT_CODE=0

  echo ""
  echo ">>> FASE: $PHASE_NAME — $(date)"

  # Ejecutar el script y capturar su exit code real por separado
  set +e
  bash "$SCRIPT_PATH" 2>&1 | tee "$PHASE_LOG"
  EXIT_CODE="${PIPESTATUS[0]}"
  set -e

  if [ "$EXIT_CODE" -eq 0 ]; then
    echo "<<< FASE: $PHASE_NAME — OK (exit 0)"
  else
    echo "<<< FASE: $PHASE_NAME — FALLIDA (exit $EXIT_CODE) ❌"
    echo ""
    echo "  Log de la fase:  cat $PHASE_LOG"
    echo "  Log global:      cat $GLOBAL_LOG"
    echo "  Todos los logs:  ls -lh $LOG_DIR/"
    exit "$EXIT_CODE"
  fi
}

# ── Escribir scripts al disco ──────────────────────────────────────
# templatefile() de Terraform ya expandió ${script_XX} antes de que
# este script llegue a la instancia. Los escribimos en disco para
# que run_phase() los ejecute como archivos independientes.
# No usamos heredoc con 'SCRIPT' porque el contenido ya está expandido
# y puede contener secuencias que confundirían al heredoc.

# CORRECCIÓN BUG 2: usar printf '%s\n' para escribir el contenido
# de forma segura, sin riesgo de que caracteres especiales
# del contenido interfieran con el delimitador del heredoc.

printf '%s\n' '${script_01_swap}'      > "$SCRIPT_DIR/common/01-swap.sh"
printf '%s\n' '${script_02_modules}'   > "$SCRIPT_DIR/common/02-kernel-modules.sh"
printf '%s\n' '${script_03_sysctl}'    > "$SCRIPT_DIR/common/03-sysctl.sh"
printf '%s\n' '${script_04_containerd}' > "$SCRIPT_DIR/common/04-containerd.sh"
printf '%s\n' '${script_05_kubernetes}' > "$SCRIPT_DIR/common/05-kubernetes.sh"
printf '%s\n' '${script_06_role}'      > "$SCRIPT_DIR/$NODE_ROLE/06-role.sh"

chmod +x \
  "$SCRIPT_DIR/common/01-swap.sh" \
  "$SCRIPT_DIR/common/02-kernel-modules.sh" \
  "$SCRIPT_DIR/common/03-sysctl.sh" \
  "$SCRIPT_DIR/common/04-containerd.sh" \
  "$SCRIPT_DIR/common/05-kubernetes.sh" \
  "$SCRIPT_DIR/$NODE_ROLE/06-role.sh"

# ── Ejecutar fases en orden ────────────────────────────────────────
run_phase "01-swap"           "$SCRIPT_DIR/common/01-swap.sh"
run_phase "02-kernel-modules" "$SCRIPT_DIR/common/02-kernel-modules.sh"
run_phase "03-sysctl"         "$SCRIPT_DIR/common/03-sysctl.sh"
run_phase "04-containerd"     "$SCRIPT_DIR/common/04-containerd.sh"
run_phase "05-kubernetes"     "$SCRIPT_DIR/common/05-kubernetes.sh"
run_phase "06-$NODE_ROLE"     "$SCRIPT_DIR/$NODE_ROLE/06-role.sh"

echo ""
echo "======================================================"
echo "COMPLETADO: $(date)"
echo "Nodo $(hostname -s) — todas las fases OK"
echo "Logs en: $LOG_DIR/"
echo "======================================================"
