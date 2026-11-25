#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# FASE 06 (Worker): kubeadm join
# Polling SSM hasta recibir señal del control-plane.
# Solo acepta un join-command que apunte a la IP privada del control
# plane ACTUAL (la pasa Terraform): los parámetros SSM tienen
# ignore_changes y pueden conservar el join de un clúster anterior.
# Realiza Health Check activo al API Server antes de ejecutar join.
# Máximo de espera en SSM: 40 × 30s = 20 minutos.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

ENV_PREFIX="${env_prefix}"
REGION="${aws_region}"
CP_PRIVATE_IP="${cp_private_ip}"
EXPECTED_ENDPOINT="$CP_PRIVATE_IP:6443"

echo "[06-kubeadm-join] Iniciando en $(hostname -s)..."
echo "[06-kubeadm-join] Control plane esperado: $EXPECTED_ENDPOINT"

# Polling: esperar señal del control-plane en SSM Y un join-command vigente
echo "[06-kubeadm-join] Esperando señal del control-plane..."
READY=false
STALE_SEEN=false
JOIN_CMD=""
CP_ENDPOINT=""
for i in $(seq 1 40); do
  CP_READY=$(aws ssm get-parameter --name "/$ENV_PREFIX/cp-ready" --query "Parameter.Value" --region "$REGION" \
    --output text 2>/dev/null || echo "false")

  if [ "$CP_READY" = "true" ]; then
    JOIN_CMD=$(aws ssm get-parameter --name "/$ENV_PREFIX/join-command" --query "Parameter.Value" --region "$REGION" \
      --with-decryption --output text 2>/dev/null || echo "")
    CP_ENDPOINT=$(echo "$JOIN_CMD" | awk '{print $3}')

    if [ "$CP_ENDPOINT" = "$EXPECTED_ENDPOINT" ]; then
      echo "[06-kubeadm-join] Control-plane listo y join-command vigente ($CP_ENDPOINT, intento $i)"
      READY=true
      break
    fi

    STALE_SEEN=true
    echo "[06-kubeadm-join] Intento $i/40: join-command obsoleto (apunta a '$CP_ENDPOINT', se espera '$EXPECTED_ENDPOINT'). Esperando 30s..."
  else
    echo "[06-kubeadm-join] Intento $i/40: no listo. Esperando 30s..."
  fi
  sleep 30
done

if [ "$READY" != "true" ]; then
  if [ "$STALE_SEEN" = "true" ]; then
    echo "[06-kubeadm-join] ERROR: timeout — SSM solo tenía un join-command obsoleto (otro control plane)"
  else
    echo "[06-kubeadm-join] ERROR: timeout — control-plane no señalizó en 20 minutos"
  fi
  exit 1
fi

# Validar formato del join command
if ! echo "$JOIN_CMD" | grep -qE "^kubeadm join .+ --token .+ --discovery-token-ca-cert-hash"; then
  echo "[06-kubeadm-join] ERROR: join command con formato inesperado"
  echo "[06-kubeadm-join] Valor recibido: $JOIN_CMD"
  exit 1
fi
echo "[06-kubeadm-join] Formato del join command validado"

# CP_ENDPOINT (IP:puerto) ya se extrajo y validó en el bucle de espera
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
$JOIN_CMD --node-name "$NODE_NAME"

echo "[06-kubeadm-join] $(hostname -s) unido al clúster correctamente"
echo "[06-kubeadm-join] OK"