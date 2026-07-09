aws_region        = "us-east-1"
project_name      = "gleamgoods"
business_division = "retail"

db_secret_name = "gleamgoods-db-secret"

tags = {
  Terraform   = "true"
  Environment = "gleamgoods"
  Project     = "GleamGoods"
  ManagedBy   = "platform-team"
}
