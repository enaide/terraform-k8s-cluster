terraform {
  required_version = ">= 1.6"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
  backend "s3" {
    bucket = "devops-myapp-bucket"
    key = "myapp/state.tfstate"
    region = "eu-south-2"
    profile = "dev"
  }
}