# --------------------------------------------------------------------
# Rotation Lambdas (AWS-managed, deployed from the Serverless Application
# Repository - "alternating users" / multi-user rotation scheme)
# --------------------------------------------------------------------
# Each Lambda only ever regenerates the password of the currently-INACTIVE
# app user (catalog_app's clone / orders_app's clone), using the shared
# master secret (superuserSecretArn) purely to run ALTER USER as admin.
# The RDS master account itself is never touched by these Lambdas.

resource "aws_serverlessapplicationrepository_cloudformation_stack" "catalog_rotation" {
  name           = "${local.name}-catalog-db-rotation"
  application_id = "arn:aws:serverlessrepo:us-east-1:${var.sar_publisher_account_id}:applications/SecretsManagerRDSMySQLRotationMultiUser"
  capabilities   = ["CAPABILITY_IAM", "CAPABILITY_RESOURCE_POLICY", "CAPABILITY_AUTO_EXPAND"]

  parameters = {
    endpoint            = "https://secretsmanager.${var.aws_region}.amazonaws.com"
    functionName        = "${local.name}-catalog-db-rotation"
    superuserSecretArn  = aws_secretsmanager_secret.catalog_db_master_secret.arn
    vpcSecurityGroupIds = aws_security_group.catalog_rotation_lambda_sg.id
    vpcSubnetIds        = join(",", data.terraform_remote_state.vpc.outputs.private_subnet_ids)
    # MySQL 8.0 supports up to 32-char usernames; the SAR default of 16
    # is too small to fit "catalog_app" + the Lambda's "_clone" suffix.
    usernameLimit = "32"
    # Default excludeCharacters (/@"'\) still lets through punctuation
    # (observed: %, >) that breaks the app's DSN string construction.
    # Alphanumeric-only avoids that entire class of bug.
    excludePunctuation = "true"
  }
}

resource "aws_serverlessapplicationrepository_cloudformation_stack" "orders_rotation" {
  name           = "${local.name}-orders-db-rotation"
  application_id = "arn:aws:serverlessrepo:us-east-1:${var.sar_publisher_account_id}:applications/SecretsManagerRDSPostgreSQLRotationMultiUser"
  capabilities   = ["CAPABILITY_IAM", "CAPABILITY_RESOURCE_POLICY", "CAPABILITY_AUTO_EXPAND"]

  parameters = {
    endpoint            = "https://secretsmanager.${var.aws_region}.amazonaws.com"
    functionName        = "${local.name}-orders-db-rotation"
    superuserSecretArn  = aws_secretsmanager_secret.orders_db_master_secret.arn
    vpcSecurityGroupIds = aws_security_group.orders_rotation_lambda_sg.id
    vpcSubnetIds        = join(",", data.terraform_remote_state.vpc.outputs.private_subnet_ids)
    # See matching comment in catalog_rotation above - default
    # excludeCharacters still allows punctuation (observed: <) that can
    # break the app's DSN string construction. Alphanumeric-only avoids it.
    excludePunctuation = "true"
  }
}

output "catalog_rotation_lambda_arn" {
  description = "ARN of the Catalog rotation Lambda (verify the output key matches once deployed: terraform state show <this resource> )"
  value       = aws_serverlessapplicationrepository_cloudformation_stack.catalog_rotation.outputs["RotationLambdaARN"]
}

output "orders_rotation_lambda_arn" {
  description = "ARN of the Orders rotation Lambda (verify the output key matches once deployed: terraform state show <this resource> )"
  value       = aws_serverlessapplicationrepository_cloudformation_stack.orders_rotation.outputs["RotationLambdaARN"]
}
