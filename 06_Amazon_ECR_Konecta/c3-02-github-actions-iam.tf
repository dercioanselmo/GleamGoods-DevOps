# =============================================
# GitHub OIDC Provider
# =============================================
resource "aws_iam_openid_connect_provider" "github" {
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
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # One entry per repo — any ref (branches/tags/PRs)
            "token.actions.githubusercontent.com:sub" = [
              for repo in var.github_repos : "repo:${repo}:*"
            ]
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