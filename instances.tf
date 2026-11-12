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
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.env_prefix}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3-scripts-policy" {
  name = "${var.env_prefix}-s3-scripts-policy"
  role = aws_iam_role.k8s-ssm-role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.k8s-scripts.arn,
        "${aws_s3_bucket.k8s-scripts.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "k8s-profile" {
  name = "${var.env_prefix}-instance-profile"
  role = aws_iam_role.k8s-ssm-role.name
}

locals {
  # Solo lo que necesita templatefile() — los 4 scripts file() puro
  # se mueven a file() directo en s3_scripts.tf
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
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/bootstrap.sh.tpl", {
    bucket    = aws_s3_bucket.k8s-scripts.id
    region    = var.aws_region
    node_role = "control-plane"
  })
  
  # ← AÑADIDO: garantiza que TODOS los scripts están en S3 antes de lanzar la EC2
  depends_on = [
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
  count = 1

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
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/bootstrap.sh.tpl", {
    bucket    = aws_s3_bucket.k8s-scripts.id
    region    = var.aws_region
    node_role = "worker"
  })
  
  # ← AÑADIDO: scripts en S3 + control plane listo antes de lanzar workers
  depends_on = [
    aws_instance.control_plane,
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