#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# FASE 05: Binarios de Kubernetes
# kubelet se habilita pero NO arranca — kubeadm lo controla.
# K8S_VERSION es inyectada por templatefile() desde Terraform.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

K8S_VERSION="${k8s_version}"

# CORRECCIÓN: validar que la variable no está vacía antes de usarla
if [ -z "$K8S_VERSION" ]; then
  echo "[05-kubernetes] ERROR: K8S_VERSION está vacía — revisar terraform.tfvars"
  exit 1
fi
echo "[05-kubernetes] Iniciando con versión: $K8S_VERSION"

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/rpm/repodata/repomd.xml.key
EOF
echo "[05-kubernetes] Repositorio configurado"

# Verificar que el repo es alcanzable antes de intentar instalar
if ! dnf repolist | grep -q "kubernetes"; then
  echo "[05-kubernetes] ERROR: repositorio kubernetes no disponible"
  dnf repolist
  exit 1
fi
echo "[05-kubernetes] Repositorio kubernetes accesible: OK"

dnf install -y kubelet kubeadm kubectl
echo "[05-kubernetes] kubelet, kubeadm y kubectl instalados"

systemctl enable kubelet
echo "[05-kubernetes] kubelet habilitado (kubeadm lo iniciará en su momento)"

# Verificar binarios y sus versiones instaladas
for bin in kubelet kubeadm kubectl; do
  BIN_PATH=$(command -v "$bin" 2>/dev/null || true)
  if [ -z "$BIN_PATH" ]; then
    echo "[05-kubernetes] ERROR: '$bin' no encontrado en PATH"
    exit 1
  fi
  BIN_VERSION=$("$bin" version --client --short 2>/dev/null \
    || "$bin" version 2>/dev/null | head -1 \
    || echo "versión no determinada")
  echo "[05-kubernetes] $bin → $BIN_PATH ($BIN_VERSION)"
done

echo "[05-kubernetes] OK"
