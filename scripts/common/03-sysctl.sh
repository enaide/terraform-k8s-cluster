#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# FASE 03: Parámetros sysctl
# Habilitan que el tráfico entre pods pase por iptables y que
# la instancia reenvíe paquetes entre interfaces de red.
# Sin estos parámetros los pods no se comunican entre nodos.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

readonly K8S_SYSCTL_FILE="/etc/sysctl.d/k8s.conf"

# 1. Definición de la lista de parámetros (Array nativo de Bash)
readonly K8S_SYSCTL_PARAMS=(
  "net.bridge.bridge-nf-call-iptables"
  "net.bridge.bridge-nf-call-ip6tables"
  "net.ipv4.ip_forward"
)
echo "[03-sysctl] Iniciando..."

# 2. Creación dinámica del archivo de configuración usando el array
echo "[03-sysctl] Creando archivo $K8S_SYSCTL_FILE..."
: > "$K8S_SYSCTL_FILE" # Limpia o crea el archivo de forma segura
for param in "${K8S_SYSCTL_PARAMS[@]}"; do
  echo "$param = 1" >> "$K8S_SYSCTL_FILE"
done
echo "[03-sysctl] Archivo $K8S_SYSCTL_FILE creado"

# 3. Aplicar los parámetros en el sistema
sysctl --system
echo "[03-sysctl] Parámetros aplicados"

# 4. Verificar que los parámetros están activos
for param in "${K8S_SYSCTL_PARAMS[@]}"; do
  VALUE=$(sysctl -n "$param")
  if [ "$VALUE" != "1" ]; then
    echo "[03-sysctl] ERROR: $param = $VALUE (esperado: 1)" >&2
    exit 1
  fi
  echo "[03-sysctl] $param = $VALUE OK"
done
echo "[03-sysctl] OK"
