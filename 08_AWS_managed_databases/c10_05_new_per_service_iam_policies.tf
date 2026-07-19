# --------------------------------------------------------------------
# New per-service IAM policies (additive)
# --------------------------------------------------------------------
# Each Pod Identity role gets an ADDITIONAL policy scoped only to its own
# new secret, attached alongside (not replacing) the legacy shared-secret
# policy in c5_02. This is intentionally additive so applying it has zero
# effect on currently running pods or the CSI driver's existing access -
# it only grants new permissions, it doesn't revoke old ones.
#
# Cleanup (do this ONLY after values-catalog.yaml / values-orders.yaml have
# been repointed at the new secret names and the app is confirmed healthy):
#   1. Delete aws_iam_role_policy_attachment.catalog_db_secret_attach (c6_05)
#      and .orders_postgresql_db_secret_attach (c9_04)
#   2. Delete aws_iam_policy.retailstore_db_secret_policy (c5_02)
#   3. Rename these two attachments/policies if you want to drop the
#      "_new_"/"_v2" naming at that point (optional, cosmetic).

resource "aws_iam_policy" "catalog_db_secret_policy" {
  name        = "${local.name}-catalog-db-secret-policy"
  description = "Allows access to gleamgoods-catalog-db-secret* in AWS Secrets Manager"
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
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.catalog_db_secret_name}*"
      }
    ]
  })
}

resource "aws_iam_policy" "orders_db_secret_policy" {
  name        = "${local.name}-orders-db-secret-policy"
  description = "Allows access to gleamgoods-orders-db-secret* in AWS Secrets Manager"
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
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.orders_db_secret_name}*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "catalog_new_db_secret_attach" {
  policy_arn = aws_iam_policy.catalog_db_secret_policy.arn
  role       = aws_iam_role.catalog_getsecrets.name
}

resource "aws_iam_role_policy_attachment" "orders_new_db_secret_attach" {
  policy_arn = aws_iam_policy.orders_db_secret_policy.arn
  role       = aws_iam_role.orders_postgresql_getsecrets.name
}

output "catalog_db_secret_policy_arn" {
  description = "IAM Policy ARN for gleamgoods-catalog-db-secret access"
  value       = aws_iam_policy.catalog_db_secret_policy.arn
}

output "orders_db_secret_policy_arn" {
  description = "IAM Policy ARN for gleamgoods-orders-db-secret access"
  value       = aws_iam_policy.orders_db_secret_policy.arn
}
