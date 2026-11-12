#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# FASE 06 (Control Plane): kubeadm init
# IP privada para anuncio interno, IP pública en SAN del certificado.
# Publica join command en SSM en cuanto el API Server está funcional.
# CNI: Calico v3.28 con VXLAN cross-subnet (óptimo para AWS single-AZ)
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

POD_CIDR="${pod_network_cidr}"     # debe ser 192.168.0.0/16 para Calico
ENV_PREFIX="${env_prefix}"
REGION="${aws_region}"

echo "[06-kubeadm-init] Iniciando..."

# ── IPs del metadata service (IMDSv2) ─────────────────────────────────────
IMDS_TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

if [ -z "$IMDS_TOKEN" ]; then
  echo "[06-kubeadm-init] ERROR: no se pudo obtener token IMDSv2"
  exit 1
fi

PRIVATE_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

if [ -z "$PRIVATE_IP" ] || [ -z "$PUBLIC_IP" ]; then
  echo "[06-kubeadm-init] ERROR: no se pudieron obtener las IPs del metadata service"
  exit 1
fi
echo "[06-kubeadm-init] IP privada: $PRIVATE_IP | IP pública: $PUBLIC_IP"

# ── Esperar socket de containerd ───────────────────────────────────────────
echo "[06-kubeadm-init] Esperando socket de containerd..."
SOCKET="/run/containerd/containerd.sock"
for i in $(seq 1 30); do
  if [ -S "$SOCKET" ] && systemctl is-active --quiet containerd; then
    echo "[06-kubeadm-init] containerd listo (intento $i)"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "[06-kubeadm-init] ERROR: containerd no disponible tras 30 intentos"
    systemctl status containerd --no-pager || true
    exit 1
  fi
  echo "[06-kubeadm-init] containerd no listo aún, esperando 5s... ($i/30)"
  sleep 5
done

# ── kubeadm init ───────────────────────────────────────────────────────────
echo "[06-kubeadm-init] Ejecutando kubeadm init..."
kubeadm init --pod-network-cidr="$POD_CIDR" --node-name="$(hostname -s)" \
  --apiserver-advertise-address="$PRIVATE_IP" \
  --apiserver-cert-extra-sans="$PUBLIC_IP"
echo "[06-kubeadm-init] kubeadm init completado"

# ── kubectl para ec2-user ──────────────────────────────────────────────────
mkdir -p /home/ec2-user/.kube
cp /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
chown -R ec2-user:ec2-user /home/ec2-user/.kube
echo "[06-kubeadm-init] kubectl configurado para ec2-user"

export KUBECONFIG=/etc/kubernetes/admin.conf

# ── Instalar Calico CNI ────────────────────────────────────────────────────
echo "[06-kubeadm-init] Instalando operador Tigera (Calico)..."
kubectl create -f \
  https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml

echo "[06-kubeadm-init] Esperando a que tigera-operator esté disponible..."
for i in $(seq 1 24); do
  READY_REPLICAS=$(kubectl get deployment tigera-operator -n tigera-operator \
    --no-headers -o custom-columns="READY:.status.readyReplicas" 2>/dev/null || echo "0")

  if [ "$READY_REPLICAS" = "1" ]; then
    echo "[06-kubeadm-init] tigera-operator listo (intento $i)"
    break
  fi
  if [ "$i" -eq 24 ]; then
    echo "[06-kubeadm-init] ERROR: tigera-operator no disponible tras 6 minutos"
    kubectl get pods -n tigera-operator || true
    exit 1
  fi
  echo "[06-kubeadm-init] tigera-operator no listo aún ($i/24), esperando 15s..."
  sleep 15
done

echo "[06-kubeadm-init] Aplicando Installation CR de Calico..."
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: ${pod_network_cidr}
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF
echo "[06-kubeadm-init] Installation CR aplicado"

# ── Verificación del API Server ────────────────────────────────────────────
echo "[06-kubeadm-init] Verificando respuesta local del API Server..."
for i in $(seq 1 30); do
  if kubectl get nodes &>/dev/null; then
    echo "[06-kubeadm-init] API Server respondiendo a kubectl OK"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "[06-kubeadm-init] ERROR: API Server no respondió tras 2.5 minutos"
    exit 1
  fi
  echo "[06-kubeadm-init] Esperando API Server... ($i/30)"
  sleep 5
done

# ── Publicar en SSM ────────────────────────────────────────────────────────
echo "[06-kubeadm-init] Generando y publicando join command en SSM..."
JOIN_CMD=$(kubeadm token create --print-join-command)

aws ssm put-parameter --name "/$ENV_PREFIX/join-command" --value "$JOIN_CMD" --type "SecureString" --overwrite --region "$REGION"
echo "[06-kubeadm-init] join-command publicado"

aws ssm put-parameter --name "/$ENV_PREFIX/cp-ready" --value "true" --type "String" --overwrite --region "$REGION"
echo "[06-kubeadm-init] Señal control-plane-ready publicada"

echo "[06-kubeadm-init] OK"