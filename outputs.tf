output "aws_ami_id" {
  value       = module.myapp-server.ami.id
  description = "ID de la AMI listo para ser consumido"
}

output "ec2_public_ip" {
  value = module.myapp-server.instance.public_ip
}
