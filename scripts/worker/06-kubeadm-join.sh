#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# FASE 06 (Worker): kubeadm join
# Polling SSM hasta recibir señal del control-plane.
# Valida el formato del join command antes de ejecutarlo.
# Máximo de espera: 40 × 30s = 20 minutos.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

ENV_PREFIX="${env_prefix}"
REGION="${aws_region}"

echo "[06-kubeadm-join] Iniciando en $(hostname -s)..."

# Polling: esperar señal del control-plane en SSM
echo "[06-kubeadm-join] Esperando señal del control-plane..."
READY=false
for i in $(seq 1 40); do
  CP_READY=$(aws ssm get-parameter \
    --name "/$ENV_PREFIX/control-plane-ready" \
    --region "$REGION" \
    --query "Parameter.Value" \
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
JOIN_CMD=$(aws ssm get-parameter \
  --name "/$ENV_PREFIX/join-command" \
  --with-decryption \
  --region "$REGION" \
  --query "Parameter.Value" \
  --output text)

if [ -z "$JOIN_CMD" ]; then
  echo "[06-kubeadm-join] ERROR: join command vacío desde SSM"
  exit 1
fi

# CORRECCIÓN: validar formato del join command antes de ejecutarlo
# Debe empezar con 'kubeadm join' y contener --token y --discovery-token-ca-cert-hash
if ! echo "$JOIN_CMD" | grep -qE "^kubeadm join .+ --token .+ --discovery-token-ca-cert-hash"; then
  echo "[06-kubeadm-join] ERROR: join command con formato inesperado"
  echo "[06-kubeadm-join] Valor recibido: $JOIN_CMD"
  exit 1
fi
echo "[06-kubeadm-join] Formato del join command validado"

# Ejecutar kubeadm join extrayendo argumentos de forma explícita
# en lugar de eval, para evitar ejecución de código arbitrario
echo "[06-kubeadm-join] Ejecutando kubeadm join..."
$JOIN_CMD

echo "[06-kubeadm-join] $(hostname -s) unido al clúster correctamente"
echo "[06-kubeadm-join] OK"
