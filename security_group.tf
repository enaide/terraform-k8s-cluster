# ── CONTROL PLANE SG ──────────────────────────────────────────────────────────
resource "aws_security_group" "k8s-sg-control-plane" {
  name        = "${var.env_prefix}-sg-control-plane"
  description = "Security Group para el nodo control plane"
  vpc_id      = aws_vpc.k8s-vpc.id

  egress {
    description = "Salida total"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env_prefix}-sg-control-plane" }
}

# ── WORKER NODES SG ───────────────────────────────────────────────────────────
resource "aws_security_group" "k8s-sg-worker" {
  name        = "${var.env_prefix}-sg-worker"
  description = "Security Group para los nodos worker"
  vpc_id      = aws_vpc.k8s-vpc.id

  egress {
    description = "Salida total"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env_prefix}-sg-worker" }
}