# --------------------------------------------------------------------
# Per-database Secrets Manager secrets
# --------------------------------------------------------------------
# These are what each Konecta service actually reads at runtime (mounted
# via c8_01/c8_02) - not the shared master secret in c6_01. Each holds a
# dedicated, least-privilege DB user (created manually, see below)
# instead of the RDS master account, and gets its own rotation
# schedule/Lambda so a rotation failure on one database can never affect
# another. Exactly mirrors 08_AWS_managed_databases' c10_01, applied
# across 5 databases via for_each instead of one hand-written block per
# database.
#
# Terraform only creates the secret *container* - the initial JSON value
# is set once out-of-band (matching how gleamgoods-db-secret itself was
# created, and how 08_AWS_managed_databases' own per-service app secrets
# work) so that `terraform apply` never fights the rotation Lambda over
# secret_string. Required JSON shape (AWS RDS rotation Lambda schema):
#   {
#     "username": "cart_app",
#     "password": "<temp>",
#     "engine": "postgres",
#     "host": "konecta-cart.<...>.us-east-1.rds.amazonaws.com",
#     "port": 5432,
#     "dbname": "konecta_cart",
#     "masterarn": "<aws_secretsmanager_secret.konecta_secret.arn>"
#   }
# The dedicated app user itself (e.g. "cart_app") must also be created
# manually in that database before the first rotation - Terraform has no
# resource for creating PostgreSQL roles here, same as 08.

resource "aws_secretsmanager_secret" "konecta_app_db_secret" {
  for_each = local.konecta_service_keys

  name        = "konecta-${replace(each.key, "_", "-")}-db-secret"
  description = "Konecta ${each.key} (PostgreSQL) app-user DB credentials - auto-rotated, alternating users"

  tags = {
    Name      = "${local.name}-${each.key}-db-secret"
    Component = "Konecta"
  }
}

# --------------------------------------------------------------------
# Per-database host-qualified master secret copies (rotation Lambda use only)
# --------------------------------------------------------------------
# konecta-db-secret (c6_01) only has {username, password} - no host -
# because it's used purely as aws_db_instance master credentials via a
# Terraform local, never opened as an independent connection. The
# multi-user rotation Lambda's setSecret step needs to open its OWN
# connection to the master account, so it requires "host" (AWS also
# expects "engine"/"port"/"dbname") on the *master* secret JSON too - and
# since one shared master secret can't carry 5 different hosts, each
# database gets its own copy here, holding the SAME master
# username/password (c6_01), host-qualified for that database's own RDS
# instance. Unlike the app secrets above, Terraform CAN populate these
# automatically - every field is already known to Terraform, so there's
# no manual step for this half of it.

resource "aws_secretsmanager_secret" "konecta_app_db_master_secret" {
  for_each = local.konecta_service_keys

  name        = "konecta-${replace(each.key, "_", "-")}-db-secret-master"
  description = "Konecta ${each.key} (PostgreSQL) RDS master credentials, host-qualified for the rotation Lambda's superuserSecretArn - never mounted to application pods"

  tags = {
    Name      = "${local.name}-${each.key}-db-secret-master"
    Component = "Konecta"
  }
}

resource "aws_secretsmanager_secret_version" "konecta_app_db_master_secret_value" {
  for_each = local.konecta_databases

  secret_id = aws_secretsmanager_secret.konecta_app_db_master_secret[each.key].id
  secret_string = jsonencode({
    username  = local.konecta_master_secret_json.username
    password  = local.konecta_master_secret_json.password
    engine    = "postgres"
    host      = each.value.address
    port      = 5432
    dbname    = each.value.dbname
    masterarn = aws_secretsmanager_secret.konecta_secret.arn
  })
}

output "konecta_app_db_secret_arns" {
  description = "ARNs of each Konecta database's app-user secret (rotation Lambda target)"
  value       = { for k, v in aws_secretsmanager_secret.konecta_app_db_secret : k => v.arn }
}

output "konecta_app_db_master_secret_arns" {
  description = "ARNs of each Konecta database's host-qualified master secret copy (rotation Lambda superuserSecretArn)"
  value       = { for k, v in aws_secretsmanager_secret.konecta_app_db_master_secret : k => v.arn }
}
