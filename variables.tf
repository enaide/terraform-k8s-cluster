variable "cp_instance_type" {
  description = "Tipo EC2 del control plane (mín. 2 vCPU / 2 GB; debe ser elegible para Free Tier en esta cuenta)"
  type        = string
  default     = "c7i-flex.large"
}

variable "worker_instance_type" {
  description = "Tipo EC2 de los workers (4 GB: necesario para MongoDB x3 + ingress + EBS CSI; ver docs/lab-k8s-mongodb-helm.md)"
  type        = string
  default     = "c7i-flex.large"
}

variable "root_volume_size" {
  description = "Tamaño del disco raíz en GB (mínimo: el snapshot de la AMI, 8 GB en AL2023)"
  type        = number
}

variable "subnet_cidr_block" {
  description = "CIDR de la subnet pública"
  type        = string
}
variable "vpc_cidr_block" {
  description = "CIDR de la VPC"
  type        = string
}

variable "aws_profile" {
  description = "Perfil de la AWS CLI"
  type        = string
  default     = "dev"
}

variable "env_prefix" {
  description = "Prefijo para nombrar todos los recursos"
  type        = string
}

variable "avail_zone" {
  description = "Availability Zone para las instancias"
  type        = string
}
variable "aws_region" {
  description = "Región AWS donde desplegar el clúster"
  type        = string
}

# variable "instance_type" {
#   description = "Tipo de instancia EC2 (mín. 2 CPU / 2 GB RAM para K8s)"
#   type        = string
#   # default     = "c7i-flex.large"
# }

variable "spot_max_price" {
  description = "Precio máximo Spot en USD/hora por instancia"
  type        = string
  default     = "0.04"
}

variable "k8s_version" {
  description = "Versión de Kubernetes a instalar (rama stable)"
  type        = string
  # default     = "v1.36"
}

variable "pod_network_cidr" {
  description = "CIDR para la red de pods (Calico requiere 10.244.0.0/16 ,validar si es cierto)"
  type        = string
  # default     = "10.244.0.0/16"
}

variable "public_key_location" {
  description = "Ruta local a tu clave pública SSH"
  type        = string
  default     = "/home/enaide/.ssh/id_ed25519.pub"
}

variable "private_key_location" {
  description = "Ruta local a tu clave privada SSH"
  type        = string
  default     = "/home/enaide/.ssh/id_ed25519"
}

variable "image_name" {
  description = "imagen linux"
  type        = string
  # default     = "al2023-ami-2023.*-kernel-6.18-x86_64"
}
variable "owner" {
  description = "numero | nombre del proovedor de la imagen linux"
  type        = string
  # default     = "amazon"    
}