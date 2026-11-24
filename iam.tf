# ─────────────────────────────────────────────────────────────────────────────
# iam.tf — Identidades IAM de los nodos
#
# Un rol por tipo de nodo, con mínimo privilegio:
#
#   Control plane → PUBLICA cp-ready y join-command en SSM
#                   lee de S3: common/, control-plane/, init.sh
#   Workers       → LEEN cp-ready y join-command de SSM
#                   lee de S3: common/, worker/, init.sh
#
# Ambos conservan AmazonSSMManagedInstanceCore (Session Manager).
# ─────────────────────────────────────────────────────────────────────────────

# ── Trust policy común: "el servicio EC2 puede asumir este rol" ──────────────
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# CONTROL PLANE
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "control_plane" {
  name               = "${var.env_prefix}-control-plane-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${var.env_prefix}-control-plane-role" }
}

# Session Manager (shell sin SSH). No lo usan los scripts de arranque.
resource "aws_iam_role_policy_attachment" "control_plane_ssm_core" {
  role       = aws_iam_role.control_plane.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "control_plane" {
  # 06-kubeadm-init.sh → aws ssm put-parameter (join-command y cp-ready)
  statement {
    sid     = "PublishJoinInfo"
    actions = ["ssm:PutParameter"]
    resources = [
      aws_ssm_parameter.control_plane_ready.arn,
      aws_ssm_parameter.join_command.arn,
    ]
  }

  # bootstrap.sh.tpl → aws s3 cp --recursive necesita listar sus prefijos
  statement {
    sid       = "ListOwnScripts"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.k8s-scripts.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["common/*", "control-plane/*"]
    }
  }

  # bootstrap.sh.tpl → descarga de los scripts que le corresponden
  statement {
    sid     = "ReadOwnScripts"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.k8s-scripts.arn}/common/*",
      "${aws_s3_bucket.k8s-scripts.arn}/control-plane/*",
      "${aws_s3_bucket.k8s-scripts.arn}/init.sh",
    ]
  }
}

resource "aws_iam_role_policy" "control_plane" {
  name   = "${var.env_prefix}-control-plane-policy"
  role   = aws_iam_role.control_plane.id
  policy = data.aws_iam_policy_document.control_plane.json
}

resource "aws_iam_instance_profile" "control_plane" {
  name = "${var.env_prefix}-control-plane-profile"
  role = aws_iam_role.control_plane.name
}

# ══════════════════════════════════════════════════════════════════════════════
# WORKERS
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "worker" {
  name               = "${var.env_prefix}-worker-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${var.env_prefix}-worker-role" }
}

resource "aws_iam_role_policy_attachment" "worker_ssm_core" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "worker" {
  # 06-kubeadm-join.sh → aws ssm get-parameter (solo lectura)
  # El SecureString usa la clave aws/ssm: no hace falta permiso KMS explícito.
  statement {
    sid     = "ReadJoinInfo"
    actions = ["ssm:GetParameter"]
    resources = [
      aws_ssm_parameter.control_plane_ready.arn,
      aws_ssm_parameter.join_command.arn,
    ]
  }

  statement {
    sid       = "ListOwnScripts"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.k8s-scripts.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["common/*", "worker/*"]
    }
  }

  statement {
    sid     = "ReadOwnScripts"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.k8s-scripts.arn}/common/*",
      "${aws_s3_bucket.k8s-scripts.arn}/worker/*",
      "${aws_s3_bucket.k8s-scripts.arn}/init.sh",
    ]
  }
}

resource "aws_iam_role_policy" "worker" {
  name   = "${var.env_prefix}-worker-policy"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.env_prefix}-worker-profile"
  role = aws_iam_role.worker.name
}
