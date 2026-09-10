#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# FASE 03: Parámetros sysctl
# Habilitan que el tráfico entre pods pase por iptables y que
# la instancia reenvíe paquetes entre interfaces de red.
# Sin estos parámetros los pods no se comunican entre nodos.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

echo "[03-sysctl] Iniciando..."

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
echo "[03-sysctl] Archivo /etc/sysctl.d/k8s.conf creado"

sysctl --system
echo "[03-sysctl] Parámetros aplicados"

# Verificar que los parámetros están activos
for param in \
  net.bridge.bridge-nf-call-iptables \
  net.bridge.bridge-nf-call-ip6tables \
  net.ipv4.ip_forward; do

  VALUE=$(sysctl -n "$param")
  if [ "$VALUE" != "1" ]; then
    echo "[03-sysctl] ERROR: $param = $VALUE (esperado: 1)"
    exit 1
  fi
  echo "[03-sysctl] $param = $VALUE OK"
done

echo "[03-sysctl] OK"
