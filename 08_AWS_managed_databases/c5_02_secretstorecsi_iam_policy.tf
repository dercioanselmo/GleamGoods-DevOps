# IAM Policy: Allow access to all glemgoods-db-secrets
#
# LEGACY / shared-secret policy, kept temporarily during the rotation
# cutover (see c10_01-05). Both catalog_getsecrets and
# orders_postgresql_getsecrets roles keep this attached until the app is
# confirmed running against its new per-service secret (values-catalog.yaml
# / values-orders.yaml secretName change in both repos), then it should be
# detached and this file deleted as a follow-up cleanup change.
resource "aws_iam_policy" "retailstore_db_secret_policy" {
  name        = "${local.name}-retailstore-db-secret-policy"
  description = "Allows access to retailstore-db-secret* in AWS Secrets Manager"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.db_secret_name}*"
      }
    ]
  })
}

# Outputs
output "retailstore_db_secret_policy_arn" {
  description = "IAM Policy ARN for retailstore-db-secret access"
  value       = aws_iam_policy.retailstore_db_secret_policy.arn
}
