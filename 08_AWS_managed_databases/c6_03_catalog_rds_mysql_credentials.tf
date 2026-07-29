# Use existing AWS Secrets Manager Secret (already created manually)
data "aws_secretsmanager_secret" "gleamgoods_secret" {
  name = var.db_secret_name
}

data "aws_secretsmanager_secret_version" "gleamgoods_secret_value" {
  secret_id = data.aws_secretsmanager_secret.gleamgoods_secret.id
}

locals {
  gleamgoods_secret_json = jsondecode(data.aws_secretsmanager_secret_version.gleamgoods_secret_value.secret_string)
}
