#!/bin/bash
# wait-for-cluster.sh
# Uso: ./wait-for-cluster.sh <public-ip-cp> <env-prefix> <region> <ssh-key>
# Ejemplo: ./wait-for-cluster.sh 35.42.88.249 dev-k8s eu-south-2 ~/.ssh/id_ed25519
set -euo pipefail

# ── PARÁMETROS ────────────────────────────────────────────────────
CP_IP="${1:?Falta <public-ip-cp>}"
ENV_PREFIX="${2:?Falta <env-prefix>}"
REGION="${3:?Falta <region>}"
SSH_KEY="${4:-$HOME/.ssh/id_ed25519}"
EXPECTED_NODES="${5:-3}"
AWS_PROFILE="${6:-default}"
SSH_USER="ec2-user"


# ── CONFIGURACIÓN DE REINTENTOS (intentos / segundos entre intentos) ──
SSM_RETRIES=40;  SSM_INTERVAL=30
SSH_RETRIES=20;  SSH_INTERVAL=10
NODES_RETRIES=30; NODES_INTERVAL=10

# ── OPCIONES REUTILIZABLES (arrays) ───────────────────────────────
SSH_OPTS=(
  -i "$SSH_KEY"
  -o StrictHostKeyChecking=no
  -o ConnectTimeout=5
  -o BatchMode=yes
)
AWS_OPTS=(
  --region "$REGION"
  --profile "$AWS_PROFILE"
)

# ── CABECERA ──────────────────────────────────────────────────────
echo "════════════════════════════════════════"
echo "  Esperando cluster: $ENV_PREFIX"
echo "  Control plane:     $CP_IP"
echo "  Nodos esperados:   $EXPECTED_NODES"
echo "  AWS Profile:       $AWS_PROFILE"
echo "════════════════════════════════════════"

# ── FASE 1: Esperar señal SSM del control plane ───────────────────
echo ""
echo "▶ Fase 1/3 — Esperando señal SSM del control plane..."
for i in $(seq 1 "$SSM_RETRIES"); do
  READY=$(aws ssm get-parameter --name "/$ENV_PREFIX/cp-ready" --query "Parameter.Value" \
    --output text "${AWS_OPTS[@]}" 2>/dev/null || echo "false")

  if [ "$READY" = "true" ]; then
    echo "  ✅ Control plane listo (${i}×${SSM_INTERVAL}s)"
    break
  fi

  if [ "$i" -eq "$SSM_RETRIES" ]; then
    echo "  ❌ Timeout: control plane no señalizó en $((SSM_RETRIES * SSM_INTERVAL / 60)) minutos"
    exit 1
  fi

  echo "  ⏳ Intento $i/$SSM_RETRIES — esperando ${SSM_INTERVAL}s..."
  sleep "$SSM_INTERVAL"
done

# ── FASE 2: Esperar SSH disponible ───────────────────────────────
echo ""
echo "▶ Fase 2/3 — Esperando SSH en control plane..."
for i in $(seq 1 "$SSH_RETRIES"); do
  if ssh "${SSH_OPTS[@]}" "ec2-user@$CP_IP" "true" 2>/dev/null; then
    echo "  ✅ SSH disponible (${i}×${SSH_INTERVAL}s)"
    break
  fi

  if [ "$i" -eq "$SSH_RETRIES" ]; then
    echo "  ❌ Timeout: SSH no disponible en $((SSH_RETRIES * SSH_INTERVAL)) segundos"
    exit 1
  fi

  echo "  ⏳ Intento $i/$SSH_RETRIES — esperando ${SSH_INTERVAL}s..."
  sleep "$SSH_INTERVAL"
done

# ── FASE 3: Esperar todos los nodos Ready ─────────────────────────
echo ""
echo "▶ Fase 3/3 — Esperando $EXPECTED_NODES nodos en estado Ready..."
for i in $(seq 1 30); do
  READY_NODES=$(ssh "${SSH_OPTS[@]}" "ec2-user@$CP_IP" \
    "kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready '" \
    2>/dev/null || echo "0")

  echo "  ⏳ Intento $i/30 — nodos Ready: $READY_NODES/$EXPECTED_NODES"

  if [ "$READY_NODES" -ge "$EXPECTED_NODES" ]; then
    echo "  ✅ Todos los nodos Ready"
    break
  fi

  if [ "$i" -eq 30 ]; then
    echo "  ❌ Timeout: solo $READY_NODES/$EXPECTED_NODES nodos Ready tras 5 minutos"
    exit 1
  fi

  sleep 10
done

# ── RESULTADO FINAL ───────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  ✅ CLUSTER LISTO"
echo "════════════════════════════════════════"
ssh "${SSH_OPTS[@]}" "ec2-user@$CP_IP" "kubectl get nodes -o wide"

echo ""
echo "Para gestionar el cluster:"
echo "  ssh -i $SSH_KEY ec2-user@$CP_IP"
echo "  kubectl get nodes"