data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "k8s-ssm-role" {
  name = "${var.env_prefix}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm-policy" {
  role       = aws_iam_role.k8s-ssm-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ssm-param-policy" {
  name = "${var.env_prefix}-ssm-param-policy"
  role = aws_iam_role.k8s-ssm-role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:PutParameter",
        "ssm:GetParameter"
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.env_prefix}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "k8s-profile" {
  name = "${var.env_prefix}-instance-profile"
  role = aws_iam_role.k8s-ssm-role.name
}

# ── LOCALS: leer scripts desde disco ─────────────────────────────────────────
# Cada script se lee una vez aquí y se pasa al template del orquestador.
# Si un archivo no existe, Terraform falla en plan (antes del apply).
locals {
  script_01_swap      = file("${path.module}/scripts/common/01-swap.sh")
  script_02_modules   = file("${path.module}/scripts/common/02-kernel-modules.sh")
  script_03_sysctl    = file("${path.module}/scripts/common/03-sysctl.sh")
  script_04_containerd = file("${path.module}/scripts/common/04-containerd.sh")

  # 05 y 06 necesitan variables, así que usan templatefile()
  script_05_kubernetes = templatefile("${path.module}/scripts/common/05-kubernetes.sh", {
    k8s_version = var.k8s_version
  })

  script_06_control_plane = templatefile("${path.module}/scripts/control-plane/06-kubeadm-init.sh", {
    pod_network_cidr = var.pod_network_cidr
    env_prefix       = var.env_prefix
    aws_region       = var.aws_region
  })

  script_06_worker = templatefile("${path.module}/scripts/worker/06-kubeadm-join.sh", {
    env_prefix = var.env_prefix
    aws_region = var.aws_region
  })
}

resource "aws_key_pair" "k8s-key" {
  key_name   = "${var.env_prefix}-key"
  public_key = file(var.public_key_location)
}

# ── CONTROL PLANE ─────────────────────────────────────────────────────────────
resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.k8s-subnet.id
  vpc_security_group_ids      = [aws_security_group.k8s-sg-control-plane.id]  # ← su SG
  availability_zone           = var.avail_zone
  associate_public_ip_address = true
  key_name                    = aws_key_pair.k8s-key.key_name
  iam_instance_profile        = aws_iam_instance_profile.k8s-profile.name

  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = var.spot_max_price
      instance_interruption_behavior = "terminate"
    }
  }

  root_block_device {
    volume_size           = one(data.aws_ami.amazon_linux_2023.block_device_mappings).ebs.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # El orquestador recibe el contenido de cada script como variable
  # y los escribe en disco antes de ejecutarlos en orden
/*   user_data = templatefile("${path.module}/scripts/init.sh.tpl", {
    node_role          = "control-plane"
    script_01_swap     = local.script_01_swap
    script_02_modules  = local.script_02_modules
    script_03_sysctl   = local.script_03_sysctl
    script_04_containerd = local.script_04_containerd
    script_05_kubernetes = local.script_05_kubernetes
    script_06_role     = local.script_06_control_plane
  }) */

  tags = { Name = "${var.env_prefix}-control-plane" }
}

# ── WORKERS ───────────────────────────────────────────────────────────────────
resource "aws_instance" "worker" {
  count = 2

  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.k8s-subnet.id
  vpc_security_group_ids      = [aws_security_group.k8s-sg-worker.id]         # ← su SG
  availability_zone           = var.avail_zone
  associate_public_ip_address = true
  key_name                    = aws_key_pair.k8s-key.key_name
  iam_instance_profile        = aws_iam_instance_profile.k8s-profile.name

  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = var.spot_max_price
      instance_interruption_behavior = "terminate"
    }
  }

  root_block_device {
    volume_size           = one(data.aws_ami.amazon_linux_2023.block_device_mappings).ebs.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

/*   user_data = templatefile("${path.module}/scripts/init.sh.tpl", {
    node_role            = "worker"
    script_01_swap       = local.script_01_swap
    script_02_modules    = local.script_02_modules
    script_03_sysctl     = local.script_03_sysctl
    script_04_containerd = local.script_04_containerd
    script_05_kubernetes = local.script_05_kubernetes
    script_06_role       = local.script_06_worker
  }) */

  depends_on = [aws_instance.control_plane]

  tags = { Name = "${var.env_prefix}-worker-${count.index + 1}" }
}

# ── LIMPIEZA SSM al destruir ───────────────────────────────────────────────────

# En vez de null_resource, usar aws_ssm_parameter
# y que el user_data los lea, no los escriba
/* resource "aws_ssm_parameter" "join_command" {
  name  = "/${var.env_prefix}/join-command"
  type  = "SecureString"
  value = "placeholder"   # sobrescrito por el control plane
  
  lifecycle {
    ignore_changes = [value]  # Terraform no sobreescribe lo que escribe kubeadm
  }
} */

resource "null_resource" "cleanup_ssm" {
  triggers = {
    region     = var.aws_region
    env_prefix = var.env_prefix
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-CMD
      aws ssm delete-parameter \
        --name "/${self.triggers.env_prefix}/join-command" \
        --region ${self.triggers.region} 2>/dev/null || true

      aws ssm delete-parameter \
        --name "/${self.triggers.env_prefix}/control-plane-ready" \
        --region ${self.triggers.region} 2>/dev/null || true
    CMD
  }

  depends_on = [aws_instance.control_plane, aws_instance.worker]
}