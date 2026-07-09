# =============================================
# ECR Repositories
# =============================================
resource "aws_ecr_repository" "ecr" {
  for_each = toset(var.ecr_repositories)

  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# =============================================
# GitHub OIDC Provider
# =============================================
# Not reating it again because it already exists.
# Terraform will skip this resource.
resource "aws_iam_openid_connect_provider" "github" {
  count = 0   # Change to 1 only if I want Terraform to manage it later

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name      = "GitHub-Actions-OIDC"
    ManagedBy = "Terraform"
  }
}

# =============================================
# IAM Role for GitHub Actions
# =============================================
resource "aws_iam_role" "github_actions" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = try(aws_iam_openid_connect_provider.github[0].arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com")
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# ECR PowerUser Policy
resource "aws_iam_role_policy_attachment" "ecr_poweruser" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# Get current account ID
data "aws_caller_identity" "current" {}