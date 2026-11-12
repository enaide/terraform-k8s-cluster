# s3_scripts.tf

resource "aws_s3_bucket" "k8s-scripts" {
  bucket        = "${var.env_prefix}-bootstrap-scripts"
  force_destroy = true
  tags          = { Name = "${var.env_prefix}-bootstrap-scripts" }
}

resource "aws_s3_bucket_public_access_block" "k8s-scripts" {
  bucket                  = aws_s3_bucket.k8s-scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Subir scripts comunes ──────────────────────────────────────────
resource "aws_s3_object" "script_01_swap" {
  bucket  = aws_s3_bucket.k8s-scripts.id
  key     = "common/01-swap.sh"
  content = file("${path.module}/scripts/common/01-swap.sh")
  etag    = filemd5("${path.module}/scripts/common/01-swap.sh")
}

resource "aws_s3_object" "script_02_modules" {
  bucket  = aws_s3_bucket.k8s-scripts.id
  key     = "common/02-kernel-modules.sh"
  content = file("${path.module}/scripts/common/02-kernel-modules.sh")
  etag    = filemd5("${path.module}/scripts/common/02-kernel-modules.sh")
}

resource "aws_s3_object" "script_03_sysctl" {
  bucket  = aws_s3_bucket.k8s-scripts.id
  key     = "common/03-sysctl.sh"
  content = file("${path.module}/scripts/common/03-sysctl.sh")
  etag    = filemd5("${path.module}/scripts/common/03-sysctl.sh")
}

resource "aws_s3_object" "script_04_containerd" {
  bucket  = aws_s3_bucket.k8s-scripts.id
  key     = "common/04-containerd.sh"
  content = file("${path.module}/scripts/common/04-containerd.sh")
  etag    = filemd5("${path.module}/scripts/common/04-containerd.sh")
}

resource "aws_s3_object" "script_05_kubernetes" {
  bucket  = aws_s3_bucket.k8s-scripts.id
  key     = "common/05-kubernetes.sh"
  content = local.script_05_kubernetes
  etag    = md5(local.script_05_kubernetes)
}

resource "aws_s3_object" "script_06_control_plane" {
  bucket  = aws_s3_bucket.k8s-scripts.id
  key     = "control-plane/06-kubeadm-init.sh"
  content = local.script_06_control_plane
  etag    = md5(local.script_06_control_plane)
}

resource "aws_s3_object" "script_06_worker" {
  bucket  = aws_s3_bucket.k8s-scripts.id
  key     = "worker/06-kubeadm-join.sh"
  content = local.script_06_worker
  etag    = md5(local.script_06_worker)
}

# ── Orquestador ────────────────────────────────────────────────────
resource "aws_s3_object" "init_orchestrator" {
  bucket  = aws_s3_bucket.k8s-scripts.id
  key     = "init.sh"
  content = file("${path.module}/scripts/init.sh")
  etag    = filemd5("${path.module}/scripts/init.sh")     # ← filemd5()
}