# ── CONTROL PLANE SG ──────────────────────────────────────────────────────────
resource "aws_security_group" "k8s-sg-control-plane" {
  name        = "${var.env_prefix}-sg-control-plane"
  description = "Security Group para el nodo control plane"
  vpc_id      = aws_vpc.k8s-vpc.id

  tags = { Name = "${var.env_prefix}-sg-control-plane" }
}

# ── WORKER NODES SG ───────────────────────────────────────────────────────────
resource "aws_security_group" "k8s-sg-worker" {
  name        = "${var.env_prefix}-sg-worker"
  description = "Security Group para los nodos worker"
  vpc_id      = aws_vpc.k8s-vpc.id

  tags = { Name = "${var.env_prefix}-sg-worker" }
}