# ─────────────────────────────────────────────────────────────────────────────
# wait.tf — Valida el clúster al final del `terraform apply`.
# Ejecuta scripts/wait-for-cluster.sh en TU máquina (local-exec).
# ─────────────────────────────────────────────────────────────────────────────

resource "null_resource" "wait_for_cluster" {
  # Se vuelve a ejecutar si se reemplaza alguna instancia (cambian sus IDs)
  triggers = {
    control_plane_id = aws_instance.control_plane.id
    worker_ids       = join(",", aws_instance.worker[*].id)
  }

  provisioner "local-exec" {
    # Con interpreter = ["bash"], `command` es la ruta del script:
    # se ejecuta como `bash <ruta>`, sin necesidad de chmod +x.
    interpreter = ["bash"]
    command     = "${path.module}/scripts/wait-for-cluster.sh"

    # Parámetros por nombre en lugar de posicionales.
    # AWS_REGION y AWS_PROFILE son variables que la AWS CLI lee por sí sola,
    # así que el script no necesita pasar --region ni --profile.
    environment = {
      CP_IP          = aws_instance.control_plane.public_ip
      ENV_PREFIX     = var.env_prefix
      AWS_REGION     = var.aws_region
      AWS_PROFILE    = var.aws_profile
      SSH_KEY        = var.private_key_location
      EXPECTED_NODES = local.expected_nodes
    }
  }

  # Las instancias ya son dependencias implícitas (se referencian arriba).
  # Los parámetros SSM no se referencian, por eso se declaran aquí.
  depends_on = [
    aws_ssm_parameter.control_plane_ready,
    aws_ssm_parameter.join_command,
  ]
}
