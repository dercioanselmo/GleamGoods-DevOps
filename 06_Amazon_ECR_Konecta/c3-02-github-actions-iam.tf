# =============================================
# GitHub OIDC Provider
# Already exists in the AWS account
# =============================================
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# =============================================
# AWS Account
# =============================================
data "aws_caller_identity" "current" {}

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
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }

          StringLike = {
            # =============================================
            # Legacy GitHub OIDC subject format
            # =============================================
            # Supports repositories using the traditional
            # name-based subject claim.
            #
            # Example:
            # repo:dercioanselmo/konecta-frontend:ref:refs/heads/main
            # =============================================
            "token.actions.githubusercontent.com:sub" = concat(

              [
                for repo in var.github_repos :
                "repo:${repo}:*"
              ],

              # =============================================
              # Immutable GitHub OIDC subject format
              # =============================================
              # GitHub now includes immutable owner and
              # repository IDs in the subject claim.
              #
              # Example:
              # repo:dercioanselmo@122406765/konecta-frontend@1354080166:ref:refs/heads/main
              #
              # This pattern allows all repositories under
              # the dercioanselmo GitHub owner.
              #
              # The repository ID is matched with * because
              # the repository IDs are not stored in tfvars.
              # =============================================
              [
                "repo:dercioanselmo@122406765/*@*:ref:refs/heads/*",
                "repo:dercioanselmo@122406765/*@*:pull_request",
                "repo:dercioanselmo@122406765/*@*:environment:*"
              ]

            )
          }
        }
      }
    ]
  })

  tags = var.tags
}

# =============================================
# ECR PowerUser Policy
# =============================================
resource "aws_iam_role_policy_attachment" "ecr_poweruser" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}