terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      #version = "~> 4.30"
    }
  }
  backend "s3" {
    bucket = "devops-myapp-bucket"
    key = "myapp/state.tfstate"
    region = "eu-south-2"
  }
}