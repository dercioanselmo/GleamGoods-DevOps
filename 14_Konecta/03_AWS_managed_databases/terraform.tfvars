aws_region        = "us-east-1"
project_name      = "konecta"
business_division = "retail"

konecta_db_secret_name = "konecta-db-secret"

tags = {
  Terraform   = "true"
  Environment = "prod"
  Project     = "Konecta"
  ManagedBy   = "platform-team"
}
