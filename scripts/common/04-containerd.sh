#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# FASE 04: Containerd
# SystemdCgroup = true es crítico: sin él kubelet y containerd
# usan gestores de cgroup distintos → pods en NotReady indefinido.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

echo "[04-containerd] Iniciando..."

# Excluir el kernel del update para no invalidar módulos de la fase 02
dnf update -y --exclude=kernel*
echo "[04-containerd] Sistema actualizado (kernel excluido)"

dnf install -y containerd
echo "[04-containerd] containerd instalado"

# 1. Crear directorio de configuración si no existe
mkdir -p /etc/containerd

# 2. Generar config base e introducir SystemdCgroup ANTES de iniciar el servicio
containerd config default > /etc/containerd/config.toml
echo "[04-containerd] config.toml generado"

# Reemplazo específico para el plugin de runc/cgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 3. Verificar el cambio en el archivo
if ! grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
  echo "[04-containerd] ERROR: SystemdCgroup no se actualizó"
  grep -A2 -B2 "SystemdCgroup" /etc/containerd/config.toml || true
  exit 1
fi
echo "[04-containerd] SystemdCgroup = true verificado en config.toml"

# 4. Habilitar e iniciar containerd directamente con la configuración correcta
systemctl enable --now containerd
echo "[04-containerd] containerd habilitado e iniciado"

# 5. Verificar que el servicio está activo
if ! systemctl is-active --quiet containerd; then
  echo "[04-containerd] ERROR: containerd no está activo"
  systemctl status containerd --no-pager || true
  exit 1
fi
echo "[04-containerd] containerd activo: OK"

# 6. Verificar que el socket UNIX existe y responde
SOCKET="/run/containerd/containerd.sock"
for i in $(seq 1 10); do
  if [ -S "$SOCKET" ]; then
    echo "[04-containerd] Socket $SOCKET disponible: OK"
    break
  fi
  if [ "$i" -eq 10 ]; then
    echo "[04-containerd] ERROR: socket $SOCKET no disponible tras 10s"
    exit 1
  fi
  echo "[04-containerd] Esperando socket... intento $i/10"
  sleep 1
done

echo "[04-containerd] OK"