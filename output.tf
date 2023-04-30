output "ami_id" {
  description = "AMI ID user to create EC2"
  value       = var.ami_id
}

output "url" {
  description = "URL of the load balancer"
  value = "http://${aws_lb.app.dns_name}"
}
