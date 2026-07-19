# Use existing AWS Secrets Manager Secret (already created manually)
data "aws_secretsmanager_secret" "retailstore_secret" {
  name = var.db_secret_name
}

data "aws_secretsmanager_secret_version" "retailstore_secret_value" {
  secret_id = data.aws_secretsmanager_secret.retailstore_secret.id
}

locals {
  retailstore_secret_json = jsondecode(data.aws_secretsmanager_secret_version.retailstore_secret_value.secret_string)
}
