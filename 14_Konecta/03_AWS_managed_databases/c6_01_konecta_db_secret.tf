# --------------------------------------------------------------------
# Shared Konecta DB Secret
# --------------------------------------------------------------------
# A single AWS Secrets Manager secret (already created manually, same
# pattern as GleamGoods' "gleamgoods-db-secret") shared by every Konecta
# database and every Konecta service. Used here purely as the master
# username/password for each aws_db_instance below - it is never opened
# as an independent connection by Terraform.
#
# Required JSON shape:
#   {
#     "username": "konecta_admin",
#     "password": "<password>"
#   }

data "aws_secretsmanager_secret" "konecta_secret" {
  name = var.konecta_db_secret_name
}

data "aws_secretsmanager_secret_version" "konecta_secret_value" {
  secret_id = data.aws_secretsmanager_secret.konecta_secret.id
}

locals {
  konecta_secret_json = jsondecode(data.aws_secretsmanager_secret_version.konecta_secret_value.secret_string)
}
