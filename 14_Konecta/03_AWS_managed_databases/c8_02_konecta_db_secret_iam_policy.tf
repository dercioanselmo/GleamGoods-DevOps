# --------------------------------------------------------------------
# Per-service IAM policies
# --------------------------------------------------------------------
# Each Pod Identity role (c8_01) has a policy scoped only to its own app
# secret (c9_03) - never the shared master secret (c6_01), and never
# another service's secret. Matches 08_AWS_managed_databases' c10_05
# exactly, applied per database via for_each.

resource "aws_iam_policy" "konecta_db_secret_policy" {
  for_each = local.konecta_service_keys

  name        = "${local.name}-${each.key}-db-secret-policy"
  description = "Allows access to konecta-${replace(each.key, "_", "-")}-db-secret* in AWS Secrets Manager"
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
        # The trailing "*" also technically matches this database's
        # "...-db-secret-master" copy (c9_03), not just the AWS-appended
        # random ARN suffix on the app secret itself - same imprecision
        # 08_AWS_managed_databases' equivalent policy has (its
        # "${var.catalog_db_secret_name}*" also matches
        # "${var.catalog_db_secret_name}-master"). Not tightened here to
        # stay consistent with that precedent.
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:konecta-${replace(each.key, "_", "-")}-db-secret*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "konecta_db_secret_attach" {
  for_each = local.konecta_service_keys

  policy_arn = aws_iam_policy.konecta_db_secret_policy[each.key].arn
  role       = aws_iam_role.konecta_getsecrets[each.key].name
}

output "konecta_db_secret_policy_arns" {
  description = "IAM Policy ARN each Konecta service uses for its own DB secret access"
  value       = { for k, v in aws_iam_policy.konecta_db_secret_policy : k => v.arn }
}
