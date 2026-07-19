# --------------------------------------------------------------------
# Attach rotation schedule to each app secret
# --------------------------------------------------------------------
# rotate_immediately = false: creating/updating this resource must NOT
# trigger a rotation on its own. The first rotation is triggered manually
# (aws secretsmanager rotate-secret) as part of the cutover runbook, only
# after the app secret's initial value has been set and the app has been
# verified working against it.

resource "aws_secretsmanager_secret_rotation" "catalog_db_secret" {
  secret_id           = aws_secretsmanager_secret.catalog_db_secret.id
  rotation_lambda_arn = aws_serverlessapplicationrepository_cloudformation_stack.catalog_rotation.outputs["RotationLambdaARN"]

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  rotate_immediately = false
}

resource "aws_secretsmanager_secret_rotation" "orders_db_secret" {
  secret_id           = aws_secretsmanager_secret.orders_db_secret.id
  rotation_lambda_arn = aws_serverlessapplicationrepository_cloudformation_stack.orders_rotation.outputs["RotationLambdaARN"]

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  rotate_immediately = false
}
