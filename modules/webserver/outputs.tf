output "instance" {
  value = aws_instance.myapp-server
}

output "ami" {
  value = data.aws_ami.latest_amazon_linux
}