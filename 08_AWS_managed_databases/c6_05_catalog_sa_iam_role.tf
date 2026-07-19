# IAM Role for Pod Identity (for AWS Secrets Store CSI Driver)
resource "aws_iam_role" "catalog_getsecrets" {
  name               = "${local.name}-catalog-getsecrets-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name        = "${local.name}-catalog-getsecrets-role"
    Environment = var.project_name
    Component   = "AWS Secrets Store CSI Driver ASCP"
  }
}

# Outputs
output "catalog_sa_getsecrets_role_arn" {
  description = "IAM Role ARN for Catalog PostgreSQL Get Secrets from AWS Secrets Manager"
  value       = aws_iam_role.catalog_getsecrets.arn
}