# RDS PostgreSQL Instance - Konecta Cart
resource "aws_db_instance" "konecta_cart_postgres" {
  identifier             = "konecta-cart"
  engine                 = "postgres"
  engine_version         = "17.6"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  max_allocated_storage  = 100
  db_subnet_group_name   = aws_db_subnet_group.konecta_rds_postgresql_subnet_group.name
  vpc_security_group_ids = [aws_security_group.konecta_rds_postgresql_sg.id]

  db_name  = "konecta_cart"
  username = local.konecta_master_secret_json.username # Getting from c6_01 and AWS Secret Manager secret "konecta-db-secret"
  password = local.konecta_master_secret_json.password # Getting from c6_01 and AWS Secret Manager secret "konecta-db-secret"
  port     = 5432

  multi_az            = false
  storage_encrypted   = true
  publicly_accessible = false
  skip_final_snapshot = true

  backup_retention_period = 7
  deletion_protection     = false

  tags = {
    Name        = "${local.name}-cart-rds-postgres"
    Environment = var.project_name
  }
}

output "konecta_cart_rds_postgresql_endpoint" {
  description = "PostgreSQL RDS endpoint for the Konecta Cart microservice"
  value       = aws_db_instance.konecta_cart_postgres.endpoint
}

output "konecta_cart_rds_postgresql_db_name" {
  value = aws_db_instance.konecta_cart_postgres.db_name
}
