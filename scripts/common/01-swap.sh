#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# FASE 01: Desactivar swap
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

echo "[01-swap] Iniciando..."

# Desactivar swap en memoria
swapoff -a
echo "[01-swap] Swap desactivado en memoria"

# Comentar entradas swap en fstab para persistir tras reinicio
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
echo "[01-swap] Entradas swap comentadas en /etc/fstab"

# CORRECCIÓN: verificar que no queda swap activo
SWAP_ACTIVE=$(swapon --show 2>/dev/null | wc -l)
if [ "$SWAP_ACTIVE" -gt 0 ]; then
  echo "[01-swap] ERROR: swap sigue activo tras swapoff -a"
  swapon --show
  exit 1
fi
echo "[01-swap] Verificado: swap inactivo"

# Verificar que fstab no tiene entradas swap sin comentar
if grep -E "^\s*[^#].*\sswap\s" /etc/fstab; then
  echo "[01-swap] ERROR: quedan entradas swap activas en /etc/fstab"
  exit 1
fi
echo "[01-swap] Verificado: /etc/fstab sin entradas swap activas"

echo "[01-swap] OK"
