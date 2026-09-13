# --------------------------------------------------------------------
# Attach rotation schedule to each app secret
# --------------------------------------------------------------------
# rotate_immediately = false: creating/updating this resource must NOT
# trigger a rotation on its own. The first rotation is triggered manually
# (aws secretsmanager rotate-secret) as part of the cutover runbook, only
# after each app secret's initial value has been set and the app has been
# verified working against it. Mirrors 08_AWS_managed_databases' c10_04.

resource "aws_secretsmanager_secret_rotation" "konecta_app_db_secret" {
  for_each = local.konecta_service_keys

  secret_id           = aws_secretsmanager_secret.konecta_app_db_secret[each.key].id
  rotation_lambda_arn = aws_serverlessapplicationrepository_cloudformation_stack.konecta_rotation[each.key].outputs["RotationLambdaARN"]

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  rotate_immediately = false
}
