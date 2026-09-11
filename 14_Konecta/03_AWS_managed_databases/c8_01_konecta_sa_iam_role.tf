# IAM Role for Pod Identity (for AWS Secrets Store CSI Driver)
# Shared by every Konecta service, since there is only one Konecta DB secret.
resource "aws_iam_role" "konecta_getsecrets" {
  name               = "${local.name}-getsecrets-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name        = "${local.name}-getsecrets-role"
    Environment = var.project_name
    Component   = "AWS Secrets Store CSI Driver ASCP"
  }
}

# Outputs
output "konecta_sa_getsecrets_role_arn" {
  description = "IAM Role ARN used by every Konecta service to get the shared DB secret from AWS Secrets Manager"
  value       = aws_iam_role.konecta_getsecrets.arn
}
