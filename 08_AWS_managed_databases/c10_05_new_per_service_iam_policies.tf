# --------------------------------------------------------------------
# Per-service IAM policies
# --------------------------------------------------------------------
# Each Pod Identity role has a policy scoped only to its own secret. These
# were originally added alongside the legacy shared-secret policy during
# the cutover (kept additive so applying it had zero effect on pods still
# reading the old secret); that legacy policy (c5_02) and its attachments
# (c6_05, c9_04) have since been removed now that the app is confirmed
# running on these. The "_new_" attachment names are cosmetic leftovers
# from that transition - fine to rename later, not worth a state churn now.

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
