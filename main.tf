provider "aws" {
  profile = "dev"
}

resource "aws_vpc" "k8s-vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.env_prefix}-vpc" }
}

resource "aws_subnet" "k8s-subnet" {
  vpc_id            = aws_vpc.k8s-vpc.id
  cidr_block        = var.subnet_cidr_block
  availability_zone = var.avail_zone

  tags = { Name = "${var.env_prefix}-subnet" }
}

resource "aws_internet_gateway" "k8s-igw" {
  vpc_id = aws_vpc.k8s-vpc.id

  tags = { Name = "${var.env_prefix}-igw" }
}

resource "aws_default_route_table" "default" {
  default_route_table_id = aws_vpc.k8s-vpc.default_route_table_id

  tags = {
    Name = "${var.env_prefix}-default-main-rtb"
  }
}

resource "aws_route_table" "k8s-rtb" {
  vpc_id = aws_vpc.k8s-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s-igw.id
  }

  tags = { Name = "${var.env_prefix}-rtb" }
}

resource "aws_route_table_association" "k8s-rtb-assoc" {
  subnet_id      = aws_subnet.k8s-subnet.id
  route_table_id = aws_route_table.k8s-rtb.id
}
