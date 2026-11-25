data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = [var.owner]

  filter {
    name   = "name"
    values = [var.image_name]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "k8s-key" {
  key_name   = "${var.env_prefix}-key"
  public_key = file(var.public_key_location)
}

# ── CONTROL PLANE ─────────────────────────────────────────────────────────────
resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.cp_instance_type
  subnet_id                   = aws_subnet.k8s-subnet.id
  vpc_security_group_ids      = [aws_security_group.k8s-sg-control-plane.id] # ← su SG
  availability_zone           = var.avail_zone
  associate_public_ip_address = true
  key_name                    = aws_key_pair.k8s-key.key_name
  iam_instance_profile        = aws_iam_instance_profile.control_plane.name

  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = var.spot_max_price
      instance_interruption_behavior = "terminate"
    }
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # IMDSv2 obligatorio y salto 2: los pods (p. ej. el EBS CSI driver) están a
  # un salto de red de la instancia y necesitan llegar al servicio de metadatos.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = templatefile("${path.module}/scripts/bootstrap.sh.tpl", {
    bucket    = aws_s3_bucket.k8s-scripts.id
    region    = var.aws_region
    node_role = "control-plane"
    node_name = "control-plane"
  })

  # ← AÑADIDO: garantiza que TODOS los scripts están en S3 antes de lanzar la EC2
  depends_on = [
    # Permisos IAM efectivos ANTES de que arranque el bootstrap (aws s3 cp / ssm)
    aws_iam_role_policy.control_plane,
    aws_iam_role_policy_attachment.control_plane_ssm_core,
    aws_s3_object.script_01_swap,
    aws_s3_object.script_02_modules,
    aws_s3_object.script_03_sysctl,
    aws_s3_object.script_04_containerd,
    aws_s3_object.script_05_kubernetes,
    aws_s3_object.script_06_control_plane,
    aws_s3_object.init_orchestrator
  ]

  tags = { Name = "${var.env_prefix}-control-plane" }
}

# ── WORKERS ───────────────────────────────────────────────────────────────────
resource "aws_instance" "worker" {
  count = 2

  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.worker_instance_type
  subnet_id                   = aws_subnet.k8s-subnet.id
  vpc_security_group_ids      = [aws_security_group.k8s-sg-worker.id] # ← su SG
  availability_zone           = var.avail_zone
  associate_public_ip_address = true
  key_name                    = aws_key_pair.k8s-key.key_name
  iam_instance_profile        = aws_iam_instance_profile.worker.name

  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = var.spot_max_price
      instance_interruption_behavior = "terminate"
    }
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # IMDSv2 obligatorio y salto 2: los pods (p. ej. el EBS CSI driver) están a
  # un salto de red de la instancia y necesitan llegar al servicio de metadatos.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = templatefile("${path.module}/scripts/bootstrap.sh.tpl", {
    bucket    = aws_s3_bucket.k8s-scripts.id
    region    = var.aws_region
    node_role = "worker"
    node_name = "worker-${count.index + 1}"
  })

  # ← AÑADIDO: scripts en S3 + control plane listo antes de lanzar workers
  depends_on = [
    aws_instance.control_plane,
    # Permisos IAM efectivos ANTES de que arranque el bootstrap (aws s3 cp / ssm)
    aws_iam_role_policy.worker,
    aws_iam_role_policy_attachment.worker_ssm_core,
    aws_iam_role_policy_attachment.worker_ebs_csi,
    aws_s3_object.script_01_swap,
    aws_s3_object.script_02_modules,
    aws_s3_object.script_03_sysctl,
    aws_s3_object.script_04_containerd,
    aws_s3_object.script_05_kubernetes,
    aws_s3_object.script_06_worker,
    aws_s3_object.init_orchestrator
  ]

  tags = { Name = "${var.env_prefix}-worker-${count.index + 1}" }
}

# ── LIMPIEZA SSM al destruir ───────────────────────────────────────────────────
resource "aws_ssm_parameter" "control_plane_ready" {
  name  = "/${var.env_prefix}/cp-ready"
  type  = "String"
  value = "false"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "join_command" {
  name  = "/${var.env_prefix}/join-command"
  type  = "SecureString"
  value = "dummy-value"

  lifecycle {
    ignore_changes = [value]
  }
}
