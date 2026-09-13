# IAM Role for Pod Identity (for AWS Secrets Store CSI Driver)
# One role per Konecta database/service, each scoped only to that
# service's own app secret (c8_02) - never a role shared across services,
# matching 08_AWS_managed_databases' per-service pattern (catalog_getsecrets,
# orders_postgresql_getsecrets are separate roles, not one shared role).
resource "aws_iam_role" "konecta_getsecrets" {
  for_each = local.konecta_service_keys

  name               = "${local.name}-${each.key}-getsecrets-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name        = "${local.name}-${each.key}-getsecrets-role"
    Environment = var.project_name
    Component   = "AWS Secrets Store CSI Driver ASCP"
  }
}

# Outputs
output "konecta_sa_getsecrets_role_arns" {
  description = "IAM Role ARN each Konecta service uses to get its own DB secret from AWS Secrets Manager"
  value       = { for k, v in aws_iam_role.konecta_getsecrets : k => v.arn }
}
