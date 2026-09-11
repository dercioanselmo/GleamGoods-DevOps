# --------------------------------------------------------------------
# IAM policy granting access to the single shared Konecta DB secret
# --------------------------------------------------------------------
resource "aws_iam_policy" "konecta_db_secret_policy" {
  name        = "${local.name}-db-secret-policy"
  description = "Allows access to ${var.konecta_db_secret_name}* in AWS Secrets Manager"
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
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.konecta_db_secret_name}*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "konecta_db_secret_attach" {
  policy_arn = aws_iam_policy.konecta_db_secret_policy.arn
  role       = aws_iam_role.konecta_getsecrets.name
}

output "konecta_db_secret_policy_arn" {
  description = "IAM Policy ARN for the shared Konecta DB secret access"
  value       = aws_iam_policy.konecta_db_secret_policy.arn
}
