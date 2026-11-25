# ─────────────────────────────────────────────────────────────────────────────
# locals.tf — Valores calculados del módulo raíz (todos los locals en un sitio)
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # ── Scripts de bootstrap renderizados (consumidos en s3_scripts.tf) ────────
  # Solo estos tres necesitan variables de Terraform, por eso pasan por
  # templatefile(). Los otros cuatro scripts se suben tal cual con file().
  # Se renderizan en `terraform plan`, en tu máquina; el nodo descarga de S3
  # el texto ya resuelto.
  script_05_kubernetes = templatefile("${path.module}/scripts/common/05-kubernetes.sh", {
    k8s_version = var.k8s_version
  })

  script_06_control_plane = templatefile("${path.module}/scripts/control-plane/06-kubeadm-init.sh", {
    pod_network_cidr = var.pod_network_cidr
    env_prefix       = var.env_prefix
    aws_region       = var.aws_region
  })

  # cp_private_ip: el worker solo acepta un join-command que apunte a ESTE
  # control plane (evita usar el de un clúster anterior guardado en SSM).
  # Sin ciclo: el control plane no depende de este script; los workers sí.
  script_06_worker = templatefile("${path.module}/scripts/worker/06-kubeadm-join.sh", {
    env_prefix    = var.env_prefix
    aws_region    = var.aws_region
    cp_private_ip = aws_instance.control_plane.private_ip
  })

  # ── Validación del clúster (consumido en wait.tf) ───────────────────────────
  # Nodos esperados = 1 control plane + todos los workers.
  # Se calcula a partir de las instancias reales, así sigue al `count` de
  # aws_instance.worker sin tener que tocar este valor.
  expected_nodes = 1 + length(aws_instance.worker)
}
