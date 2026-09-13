# --------------------------------------------------------------------
# Rotation Lambdas (AWS-managed, deployed from the Serverless Application
# Repository - "alternating users" / multi-user rotation scheme)
# --------------------------------------------------------------------
# Each Lambda only ever regenerates the password of the currently-INACTIVE
# app user (e.g. cart_app's clone), using the host-qualified master secret
# copy (c9_03) purely to run ALTER USER as admin. The RDS master account
# itself is never touched by these Lambdas. Exactly mirrors
# 08_AWS_managed_databases' c10_03 (SecretsManagerRDSPostgreSQLRotationMultiUser,
# same app Orders uses there), applied per database via for_each.

resource "aws_serverlessapplicationrepository_cloudformation_stack" "konecta_rotation" {
  for_each = local.konecta_service_keys

  name           = "${local.name}-${each.key}-db-rotation"
  application_id = "arn:aws:serverlessrepo:us-east-1:${var.sar_publisher_account_id}:applications/SecretsManagerRDSPostgreSQLRotationMultiUser"
  capabilities   = ["CAPABILITY_IAM", "CAPABILITY_RESOURCE_POLICY", "CAPABILITY_AUTO_EXPAND"]

  parameters = {
    endpoint            = "https://secretsmanager.${var.aws_region}.amazonaws.com"
    functionName        = "${local.name}-${each.key}-db-rotation"
    superuserSecretArn  = aws_secretsmanager_secret.konecta_app_db_master_secret[each.key].arn
    vpcSecurityGroupIds = aws_security_group.konecta_rotation_lambda_sg[each.key].id
    vpcSubnetIds        = join(",", data.terraform_remote_state.vpc.outputs.private_subnet_ids)
    # Default excludeCharacters still lets through punctuation that has
    # broken the app's DSN string construction before (see
    # 08_AWS_managed_databases' matching comment) - alphanumeric-only
    # avoids that entire class of bug.
    excludePunctuation = "true"
  }
}

output "konecta_rotation_lambda_arns" {
  description = "ARNs of each Konecta database's rotation Lambda (verify the output key matches once deployed: terraform state show <resource>)"
  value       = { for k, v in aws_serverlessapplicationrepository_cloudformation_stack.konecta_rotation : k => v.outputs["RotationLambdaARN"] }
}
