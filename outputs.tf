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
  description = "IPs públicas de los workers"
}

output "ssh_control_plane" {
  value       = "ssh -i /home/enaide/.ssh/id_ed25519 ec2-user@${aws_instance.control_plane.public_ip}"
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
  value       = "~$0.081 USD/hr total (3 nodos Spot c7i-flex.large)"
  description = "Costo estimado del clúster completo"
}