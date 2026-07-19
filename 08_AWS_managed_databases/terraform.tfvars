aws_region        = "us-east-1"
project_name      = "gleamgoods"
business_division = "retail"

db_secret_name         = "gleamgoods-db-secret"
catalog_db_secret_name = "gleamgoods-catalog-db-secret"
orders_db_secret_name  = "gleamgoods-orders-db-secret"
rotation_days          = 30

tags = {
  Terraform   = "true"
  Environment = "gleamgoods"
  Project     = "GleamGoods"
  ManagedBy   = "platform-team"
}
