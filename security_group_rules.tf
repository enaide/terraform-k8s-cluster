# ══════════════════════════════════════════════════════════════════════════════
# REGLAS DE EGRESS (Tráfico Saliente)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_vpc_security_group_egress_rule" "cp_outbound" {
  security_group_id = aws_security_group.k8s-sg-control-plane.id
  description       = "Salida total para descarga de imagenes, actualizaciones y llamadas a API de AWS"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "worker_outbound" {
  security_group_id = aws_security_group.k8s-sg-worker.id
  description       = "Salida total para pull de imagenes de contenedor y telemetria"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ══════════════════════════════════════════════════════════════════════════════
# CONTROL PLANE - REGLAS DE ENTRADA (INGRESS)
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


# Acceso al API Server: Restringido únicamente a la IP del administrador/VPN corporativa
resource "aws_vpc_security_group_ingress_rule" "cp_k8s_api" {
  security_group_id = aws_security_group.k8s-sg-control-plane.id
  description       = "Kubernetes API Server - Restringido a CIDR de administracion"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0" # ⚠️ Definir variable con tu IP /32 o VPN corporativa
  tags              = { Name = "${var.env_prefix}-cp-k8s-api" }
}

# Permitir que los Workers llamen al API Server
resource "aws_vpc_security_group_ingress_rule" "cp_k8s_api_from_workers" {
  security_group_id            = aws_security_group.k8s-sg-control-plane.id
  description                  = "Kubernetes API Server - trafico desde Workers"
  from_port                    = 6443
  to_port                      = 6443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.k8s-sg-worker.id
  tags                         = { Name = "${var.env_prefix}-cp-k8s-api-workers" }
}

# Kubelet API en Control Plane (requerido para kubectl logs/exec y metrics-server desde el API Server)
resource "aws_vpc_security_group_ingress_rule" "cp_kubelet" {
  security_group_id            = aws_security_group.k8s-sg-control-plane.id
  description                  = "Kubelet API - trafico inter-nodo"
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.k8s-sg-control-plane.id
  tags                         = { Name = "${var.env_prefix}-cp-kubelet" }
}

# etcd (Tráfico interno estrictamente entre nodos del Control Plane)
resource "aws_vpc_security_group_ingress_rule" "cp_etcd" {
  security_group_id            = aws_security_group.k8s-sg-control-plane.id
  description                  = "etcd server client API - solo entre nodos Control Plane"
  from_port                    = 2379
  to_port                      = 2380
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.k8s-sg-control-plane.id
  tags                         = { Name = "${var.env_prefix}-cp-etcd" }
}

# ══════════════════════════════════════════════════════════════════════════════
# WORKER NODES - REGLAS DE ENTRADA (INGRESS)
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

# NodePorts para exposición de aplicaciones
resource "aws_vpc_security_group_ingress_rule" "worker_nodeport" {
  security_group_id = aws_security_group.k8s-sg-worker.id
  description       = "NodePort Services - Acceso a aplicaciones desdel el Load Balancer / Exterior"
  from_port         = 30000
  to_port           = 32767
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = { Name = "${var.env_prefix}-worker-nodeport" }
}

# Kubelet API en Workers (El Control Plane le ordena ejecutar pods, logs, exec)
resource "aws_vpc_security_group_ingress_rule" "worker_kubelet_api" {
  security_group_id            = aws_security_group.k8s-sg-worker.id
  description                  = "kubelet API - llamadas desde Control Plane"
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.k8s-sg-control-plane.id
  tags                         = { Name = "${var.env_prefix}-worker-kubelet-api" }
}

# Kube-Proxy Health Check (Tráfico interno del cluster)
resource "aws_vpc_security_group_ingress_rule" "worker_kube_proxy" {
  security_group_id            = aws_security_group.k8s-sg-worker.id
  description                  = "kube-proxy health check"
  from_port                    = 10256
  to_port                      = 10256
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.k8s-sg-worker.id
  tags                         = { Name = "${var.env_prefix}-worker-kube-proxy" }
}

# ══════════════════════════════════════════════════════════════════════════════
# CALICO CNI - COMUNICACIÓN INTER-NODO (Control Plane ↔ Workers)
# ══════════════════════════════════════════════════════════════════════════════

# Calico VXLAN Overlay (Puerto primario para la red de Pods)
resource "aws_vpc_security_group_ingress_rule" "calico_vxlan_cp" {
  security_group_id            = aws_security_group.k8s-sg-control-plane.id
  referenced_security_group_id = aws_security_group.k8s-sg-worker.id
  description                  = "Calico VXLAN overlay desde workers y cp"
  from_port                    = 4789
  to_port                      = 4789
  ip_protocol                  = "udp"
  tags                         = { Name = "${var.env_prefix}-cp-calico-vxlan" }
}

resource "aws_vpc_security_group_ingress_rule" "calico_vxlan_worker" {
  security_group_id            = aws_security_group.k8s-sg-worker.id
  referenced_security_group_id = aws_security_group.k8s-sg-control-plane.id
  description                  = "Calico VXLAN overlay desde cp y workers"
  from_port                    = 4789
  to_port                      = 4789
  ip_protocol                  = "udp"
  tags                         = { Name = "${var.env_prefix}-worker-calico-vxlan" }
}

# Permitir VXLAN entre los mismos nodos del Control Plane (cuando tienes más de un nodo máster en alta disponibilidad
resource "aws_vpc_security_group_ingress_rule" "calico_vxlan_cp_self" {
  security_group_id            = aws_security_group.k8s-sg-control-plane.id # DESTINO: Control Plane
  referenced_security_group_id = aws_security_group.k8s-sg-control-plane.id # ORIGEN: Control Plane

  ip_protocol = "udp"
  from_port   = 4789
  to_port     = 4789
  description = "Calico VXLAN overlay entre nodos del Control Plane"
  tags        = { Name = "${var.env_prefix}-cp-to-cp-vxlan" }
}

# Permitir VXLAN entre workers mismos
resource "aws_vpc_security_group_ingress_rule" "calico_vxlan_worker_self" {
  security_group_id            = aws_security_group.k8s-sg-worker.id
  referenced_security_group_id = aws_security_group.k8s-sg-worker.id
  description                  = "Calico VXLAN overlay entre workers"
  from_port                    = 4789
  to_port                      = 4789
  ip_protocol                  = "udp"
  tags                         = { Name = "${var.env_prefix}-worker-to-worker-vxlan" }
}

# Calico Typha (Solo si usas Typha para escalar +50 nodos)
resource "aws_vpc_security_group_ingress_rule" "calico_typha" {
  security_group_id            = aws_security_group.k8s-sg-control-plane.id
  referenced_security_group_id = aws_security_group.k8s-sg-worker.id
  description                  = "Calico Typha daemon"
  from_port                    = 5473
  to_port                      = 5473
  ip_protocol                  = "tcp"
  tags                         = { Name = "${var.env_prefix}-cp-calico-typha" }
}

# BGP entre control plane y workers (TCP 179)
resource "aws_vpc_security_group_ingress_rule" "cp_bgp_from_workers" {
  security_group_id            = aws_security_group.k8s-sg-control-plane.id
  referenced_security_group_id = aws_security_group.k8s-sg-worker.id
  ip_protocol                  = "tcp"
  from_port                    = 179
  to_port                      = 179
  description                  = "BGP from workers"
}

resource "aws_vpc_security_group_ingress_rule" "cp_bgp_self" {
  security_group_id            = aws_security_group.k8s-sg-control-plane.id
  referenced_security_group_id = aws_security_group.k8s-sg-control-plane.id
  ip_protocol                  = "tcp"
  from_port                    = 179
  to_port                      = 179
  description                  = "BGP self (control plane)"
}

resource "aws_vpc_security_group_ingress_rule" "worker_bgp_from_cp" {
  security_group_id            = aws_security_group.k8s-sg-worker.id
  referenced_security_group_id = aws_security_group.k8s-sg-control-plane.id
  ip_protocol                  = "tcp"
  from_port                    = 179
  to_port                      = 179
  description                  = "BGP from control plane"
}

resource "aws_vpc_security_group_ingress_rule" "worker_bgp_self" {
  security_group_id            = aws_security_group.k8s-sg-worker.id
  referenced_security_group_id = aws_security_group.k8s-sg-worker.id
  ip_protocol                  = "tcp"
  from_port                    = 179
  to_port                      = 179
  description                  = "BGP between workers"
}