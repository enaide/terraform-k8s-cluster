# ══════════════════════════════════════════════════════════════════════════════
# CONTROL PLANE RULES
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_vpc_security_group_ingress_rule" "cp_ssh" {
  security_group_id = aws_security_group.k8s-sg-control-plane.id
  description       = "SSH acceso externo"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = { Name = "${var.env_prefix}-cp-ssh" }
}

resource "aws_vpc_security_group_ingress_rule" "cp_k8s_api" {
  security_group_id = aws_security_group.k8s-sg-control-plane.id
  description       = "Kubernetes API Server"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = { Name = "${var.env_prefix}-cp-k8s-api" }
}

resource "aws_vpc_security_group_ingress_rule" "cp_etcd" {
  security_group_id = aws_security_group.k8s-sg-control-plane.id
  description       = "etcd - solo interno"
  from_port         = 2379
  to_port           = 2380
  ip_protocol       = "tcp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-cp-etcd" }
}

resource "aws_vpc_security_group_ingress_rule" "cp_scheduler" {
  security_group_id = aws_security_group.k8s-sg-control-plane.id
  description       = "kube-scheduler y kube-controller-manager"
  from_port         = 10251
  to_port           = 10252
  ip_protocol       = "tcp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-cp-scheduler" }
}

# ── Calico en control plane ────────────────────────────────────────────────

resource "aws_vpc_security_group_ingress_rule" "cp_calico_bgp" {
  security_group_id = aws_security_group.k8s-sg-control-plane.id
  description       = "Calico BGP - intercambio de rutas entre nodos"
  from_port         = 179
  to_port           = 179
  ip_protocol       = "tcp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-cp-calico-bgp" }
}

resource "aws_vpc_security_group_ingress_rule" "cp_calico_vxlan" {
  security_group_id = aws_security_group.k8s-sg-control-plane.id
  description       = "Calico VXLAN overlay"
  from_port         = 4789
  to_port           = 4789
  ip_protocol       = "udp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-cp-calico-vxlan" }
}

resource "aws_vpc_security_group_ingress_rule" "cp_calico_typha" {
  security_group_id = aws_security_group.k8s-sg-control-plane.id
  description       = "Calico Typha - sincronizacion de politicas"
  from_port         = 5473
  to_port           = 5473
  ip_protocol       = "tcp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-cp-calico-typha" }
}

resource "aws_vpc_security_group_ingress_rule" "cp_calico_wireguard" {
  security_group_id = aws_security_group.k8s-sg-control-plane.id
  description       = "Calico WireGuard - cifrado opcional entre nodos"
  from_port         = 51820
  to_port           = 51820
  ip_protocol       = "udp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-cp-calico-wireguard" }
}

# ══════════════════════════════════════════════════════════════════════════════
# WORKER NODES RULES
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_vpc_security_group_ingress_rule" "worker_ssh" {
  security_group_id = aws_security_group.k8s-sg-worker.id
  description       = "SSH acceso externo"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = { Name = "${var.env_prefix}-worker-ssh" }
}

resource "aws_vpc_security_group_ingress_rule" "worker_nodeport" {
  security_group_id = aws_security_group.k8s-sg-worker.id
  description       = "NodePort Services - acceso externo a aplicaciones"
  from_port         = 30000
  to_port           = 32767
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = { Name = "${var.env_prefix}-worker-nodeport" }
}

resource "aws_vpc_security_group_ingress_rule" "worker_kubelet_api" {
  security_group_id = aws_security_group.k8s-sg-worker.id
  description       = "kubelet API - control plane hacia workers"
  from_port         = 10250
  to_port           = 10250
  ip_protocol       = "tcp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-worker-kubelet-api" }
}

resource "aws_vpc_security_group_ingress_rule" "worker_kubelet_readonly" {
  security_group_id = aws_security_group.k8s-sg-worker.id
  description       = "kubelet read-only - metricas"
  from_port         = 10255
  to_port           = 10255
  ip_protocol       = "tcp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-worker-kubelet-readonly" }
}

resource "aws_vpc_security_group_ingress_rule" "worker_kube_proxy" {
  security_group_id = aws_security_group.k8s-sg-worker.id
  description       = "kube-proxy health check"
  from_port         = 10256
  to_port           = 10256
  ip_protocol       = "tcp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-worker-kube-proxy" }
}

# ── Calico en workers ──────────────────────────────────────────────────────

resource "aws_vpc_security_group_ingress_rule" "worker_calico_bgp" {
  security_group_id = aws_security_group.k8s-sg-worker.id
  description       = "Calico BGP - intercambio de rutas entre nodos"
  from_port         = 179
  to_port           = 179
  ip_protocol       = "tcp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-worker-calico-bgp" }
}

resource "aws_vpc_security_group_ingress_rule" "worker_calico_vxlan" {
  security_group_id = aws_security_group.k8s-sg-worker.id
  description       = "Calico VXLAN overlay"
  from_port         = 4789
  to_port           = 4789
  ip_protocol       = "udp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-worker-calico-vxlan" }
}

resource "aws_vpc_security_group_ingress_rule" "worker_calico_typha" {
  security_group_id = aws_security_group.k8s-sg-worker.id
  description       = "Calico Typha - sincronizacion de politicas"
  from_port         = 5473
  to_port           = 5473
  ip_protocol       = "tcp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-worker-calico-typha" }
}

resource "aws_vpc_security_group_ingress_rule" "worker_calico_wireguard" {
  security_group_id = aws_security_group.k8s-sg-worker.id
  description       = "Calico WireGuard - cifrado opcional entre nodos"
  from_port         = 51820
  to_port           = 51820
  ip_protocol       = "udp"
  cidr_ipv4         = var.subnet_cidr_block
  tags              = { Name = "${var.env_prefix}-worker-calico-wireguard" }
}