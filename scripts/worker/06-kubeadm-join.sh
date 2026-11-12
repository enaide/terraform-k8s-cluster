#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# FASE 06 (Worker): kubeadm join
# Polling SSM hasta recibir señal del control-plane.
# Realiza Health Check activo al API Server antes de ejecutar join.
# Máximo de espera en SSM: 40 × 30s = 20 minutos.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

ENV_PREFIX="${env_prefix}"
REGION="${aws_region}"

echo "[06-kubeadm-join] Iniciando en $(hostname -s)..."

# Polling: esperar señal del control-plane en SSM
echo "[06-kubeadm-join] Esperando señal del control-plane..."
READY=false
for i in $(seq 1 40); do
  CP_READY=$(aws ssm get-parameter --name "/$ENV_PREFIX/cp-ready" --query "Parameter.Value" --region "$REGION" \
    --output text 2>/dev/null || echo "false")

  if [ "$CP_READY" = "true" ]; then
    echo "[06-kubeadm-join] Control-plane listo (intento $i)"
    READY=true
    break
  fi

  echo "[06-kubeadm-join] Intento $i/40: no listo. Esperando 30s..."
  sleep 30
done

if [ "$READY" != "true" ]; then
  echo "[06-kubeadm-join] ERROR: timeout — control-plane no señalizó en 20 minutos"
  exit 1
fi

# Obtener join command desde SSM
echo "[06-kubeadm-join] Obteniendo join command desde SSM..."
JOIN_CMD=$(aws ssm get-parameter --name "/$ENV_PREFIX/join-command" --query "Parameter.Value" --region "$REGION" \
  --with-decryption \
  --output text)

if [ -z "$JOIN_CMD" ]; then
  echo "[06-kubeadm-join] ERROR: join command vacío desde SSM"
  exit 1
fi

# Validar formato del join command
if ! echo "$JOIN_CMD" | grep -qE "^kubeadm join .+ --token .+ --discovery-token-ca-cert-hash"; then
  echo "[06-kubeadm-join] ERROR: join command con formato inesperado"
  echo "[06-kubeadm-join] Valor recibido: $JOIN_CMD"
  exit 1
fi
echo "[06-kubeadm-join] Formato del join command validado"

# Extraer IP y puerto para el Health Check de red previo
CP_ENDPOINT=$(echo "$JOIN_CMD" | awk '{print $3}')

echo "[06-kubeadm-join] Verificando conectividad HTTP/2 con el API Server en https://$CP_ENDPOINT/healthz..."
for i in $(seq 1 30); do
  if curl -k -s "https://$CP_ENDPOINT/healthz" | grep -q "ok"; then
    echo "[06-kubeadm-join] Conexión exitosa con el API Server (intento $i)"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "[06-kubeadm-join] ERROR: No se pudo establecer conexión HTTP/2 con https://$CP_ENDPOINT/healthz tras 2.5 minutos"
    exit 1
  fi
  echo "[06-kubeadm-join] API Server sin respuesta aún, reintentando en 5s... ($i/30)"
  sleep 5
done

# Ejecutar kubeadm join
echo "[06-kubeadm-join] Ejecutando kubeadm join..."
$JOIN_CMD

echo "[06-kubeadm-join] $(hostname -s) unido al clúster correctamente"
echo "[06-kubeadm-join] OK"