resource "null_resource" "wait_for_cluster" {
  # Se re-ejecuta si cambian las IPs de los nodos
  triggers = {
    control_plane_id = aws_instance.control_plane.id
    worker_ids       = join(",", aws_instance.worker[*].id)
  }

  provisioner "local-exec" {
    command = <<-EOT
      chmod +x ${path.module}/scripts/wait-for-cluster.sh
      ${path.module}/scripts/wait-for-cluster.sh \
        ${aws_instance.control_plane.public_ip} \
        ${var.env_prefix} \
        ${var.aws_region} \
        ${var.private_key_location} \
        3 \
        dev
    EOT
    interpreter = ["bash", "-c"]
  }

  depends_on = [
    aws_instance.control_plane,
    aws_instance.worker,
    aws_ssm_parameter.control_plane_ready,
    aws_ssm_parameter.join_command,
  ]
}