output "endpoint" {
  description = "RDS endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "address" {
  description = "RDS hostname"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "master_username" {
  description = "Master username"
  value       = aws_db_instance.main.username
}

output "master_password" {
  description = "Master password (sensitive)"
  value       = random_password.master.result
  sensitive   = true
}

output "security_group_id" {
  description = "Security group ID of the RDS instance"
  value       = aws_security_group.rds.id
}
