#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# FASE 02: Módulos de kernel
# overlay      → capas del sistema de archivos para contenedores
# br_netfilter → iptables puede inspeccionar tráfico de bridges
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

echo "[02-kernel-modules] Iniciando..."

cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
echo "[02-kernel-modules] /etc/modules-load.d/k8s.conf creado"

modprobe overlay
echo "[02-kernel-modules] overlay cargado"

modprobe br_netfilter
echo "[02-kernel-modules] br_netfilter cargado"

# CORRECCIÓN: verificar cada módulo por separado con grep de línea completa
# para evitar falsos positivos con nombres similares (ej. overlay_fs)
for mod in overlay br_netfilter; do
  if ! lsmod | awk '{print $1}' | grep -qx "$mod"; then
    echo "[02-kernel-modules] ERROR: módulo '$mod' no está cargado"
    echo "[02-kernel-modules] lsmod completo:"
    lsmod
    exit 1
  fi
  echo "[02-kernel-modules] Módulo '$mod' activo: OK"
done

echo "[02-kernel-modules] OK"
