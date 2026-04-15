output "vpc_id" {
  value = aws_vpc.main.id
}

output "app_public_ip" {
  description = "Elastic IP of the application host"
  value       = aws_eip.app.public_ip
}

output "app_ssh_command" {
  description = "Convenience SSH command (assumes the matching private key is loaded)"
  value       = "ssh ubuntu@${aws_eip.app.public_ip}"
}

output "db_endpoint" {
  description = "RDS endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "db_address" {
  value = aws_db_instance.main.address
}

output "db_credentials_parameter" {
  description = "SSM Parameter Store name holding DB credentials (SecureString JSON)"
  value       = aws_ssm_parameter.db_credentials.name
}
