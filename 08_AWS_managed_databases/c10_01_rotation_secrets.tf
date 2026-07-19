# --------------------------------------------------------------------
# Per-service Secrets Manager secrets
# --------------------------------------------------------------------
# These replace the shared gleamgoods-db-secret as the credential the
# applications actually consume. Each holds a dedicated, least-privilege
# DB user (see manual SQL steps in the rotation runbook) instead of the
# RDS master account, and gets its own rotation schedule/Lambda so a
# rotation failure on one service can never affect the other.
#
# Terraform only creates the secret *container* here - the initial JSON
# value is set once out-of-band (matching how gleamgoods-db-secret itself
# was created) so that `terraform apply` never fights the rotation Lambda
# over secret_string. Required JSON shape (AWS RDS rotation Lambda schema):
#   {
#     "username": "catalog_app",
#     "password": "<temp>",
#     "engine": "mysql",
#     "host": "mydb3.cipcmuog8z8q.us-east-1.rds.amazonaws.com",
#     "port": 3306,
#     "dbname": "catalogdb",
#     "masterarn": "<data.aws_secretsmanager_secret.retailstore_secret.arn>"
#   }
# (Orders: engine "postgres", host orders-postgres-db..., port 5432, dbname "ordersdb")

resource "aws_secretsmanager_secret" "catalog_db_secret" {
  name        = var.catalog_db_secret_name
  description = "Catalog (MySQL) app-user DB credentials - auto-rotated, alternating users"

  tags = {
    Name      = "${local.name}-catalog-db-secret"
    Component = "Catalog"
  }
}

resource "aws_secretsmanager_secret" "orders_db_secret" {
  name        = var.orders_db_secret_name
  description = "Orders (PostgreSQL) app-user DB credentials - auto-rotated, alternating users"

  tags = {
    Name      = "${local.name}-orders-db-secret"
    Component = "Orders"
  }
}

# --------------------------------------------------------------------
# Per-engine master/superuser secrets (rotation Lambda use only)
# --------------------------------------------------------------------
# The original shared gleamgoods-db-secret only has {username, password} -
# no host - because it's used purely as aws_db_instance master credentials
# via a Terraform data source (c6_03/c6_04/c9_03), never opened as an
# independent connection. The multi-user rotation Lambda's setSecret step
# needs to open its OWN connection to the master account, so it requires
# "host" (AWS also expects "engine"/"port"/"dbname") on the *master* secret
# JSON too - and since gleamgoods-db-secret's username/password happen to
# be valid on both the MySQL and the Postgres instance, one shared secret
# can't carry a single correct host for both engines. Hence one master
# secret per engine here, both holding a COPY of the same master
# username/password (set out-of-band, same pattern as c10_01 above), just
# with each engine's own host/port/dbname/engine fields.
resource "aws_secretsmanager_secret" "catalog_db_master_secret" {
  name        = "${var.catalog_db_secret_name}-master"
  description = "Catalog (MySQL) RDS master credentials, host-qualified for the rotation Lambda's superuserSecretArn - never mounted to application pods"

  tags = {
    Name      = "${local.name}-catalog-db-master-secret"
    Component = "Catalog"
  }
}

resource "aws_secretsmanager_secret" "orders_db_master_secret" {
  name        = "${var.orders_db_secret_name}-master"
  description = "Orders (PostgreSQL) RDS master credentials, host-qualified for the rotation Lambda's superuserSecretArn - never mounted to application pods"

  tags = {
    Name      = "${local.name}-orders-db-master-secret"
    Component = "Orders"
  }
}

output "catalog_db_secret_arn" {
  description = "ARN of the Catalog app-user secret (rotation Lambda target)"
  value       = aws_secretsmanager_secret.catalog_db_secret.arn
}

output "orders_db_secret_arn" {
  description = "ARN of the Orders app-user secret (rotation Lambda target)"
  value       = aws_secretsmanager_secret.orders_db_secret.arn
}

output "catalog_db_master_secret_arn" {
  description = "ARN of the Catalog host-qualified master secret (rotation Lambda superuserSecretArn)"
  value       = aws_secretsmanager_secret.catalog_db_master_secret.arn
}

output "orders_db_master_secret_arn" {
  description = "ARN of the Orders host-qualified master secret (rotation Lambda superuserSecretArn)"
  value       = aws_secretsmanager_secret.orders_db_master_secret.arn
}
