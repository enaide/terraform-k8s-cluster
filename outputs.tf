output "control_plane_public_ip" {
  value       = aws_instance.control_plane.public_ip
  description = "IP pública del control-plane — SSH y kubectl"
}

output "control_plane_private_ip" {
  value       = aws_instance.control_plane.private_ip
  description = "IP privada — usada internamente por kubeadm"
}

output "worker_public_ips" {
  value       = aws_instance.worker[*].public_ip
  description = "IPs públicas de los workers"
}

output "worker_private_ips" {
  value       = aws_instance.worker[*].private_ip
  description = "IPs privadas de los workers"
}

output "ssh_control_plane" {
  value       = "ssh -i ${var.private_key_location} ec2-user@${aws_instance.control_plane.public_ip}"
  description = "Comando SSH directo al control-plane"
}

output "wait_for_cluster" {
  description = "El cluster fue validado automáticamente al final del apply"
  value       = "✅ Cluster validado — ${var.env_prefix} · ${var.aws_region}"
  depends_on  = [null_resource.wait_for_cluster]
}

output "watch_init_log" {
  value       = "ssh -i ${var.private_key_location} ec2-user@${aws_instance.control_plane.public_ip} 'tail -f /var/log/k8s-init/init.log'"
  description = "Monitorear progreso de kubeadm init en tiempo real"
}

output "estimated_cost_per_hour" {
  # Se calcula a partir de la configuración real. El precio Spot varía; aquí
  # se muestra el tope: spot_max_price × número de nodos.
  value = format(
    "Spot: 1× %s + %d× %s · tope máx. $%.3f USD/h (%s USD/h por nodo)",
    var.cp_instance_type,
    length(aws_instance.worker),
    var.worker_instance_type,
    tonumber(var.spot_max_price) * local.expected_nodes,
    var.spot_max_price,
  )
  description = "Coste máximo por hora del clúster (el precio Spot real suele ser menor)"
}