# =============================================
# IAM Role for GitHub Actions — Terraform CI/CD
# =============================================
# Lives here, not in a CI-applied module, on purpose: every terraform-*.yaml
# workflow across every other module (02-08) assumes this role via OIDC to
# authenticate. If it were defined in one of those CI-applied modules, that
# module's own first apply would need the role to already exist in order to
# authenticate - a chicken-and-egg bootstrap problem. This module
# (01_remote_backend_s3bucket) is the one module in the project meant to be
# applied manually (it bootstraps the S3 backend everything else uses), so
# it's the natural place for anything every other module's CI depends on to
# already exist.
#
# The OIDC provider itself (one per AWS account per issuer URL) is already
# created and owned by 06_Amazon_ECR (c3-ecr-iam.tf), predating this role -
# looked up here read-only via a data source rather than duplicated, since a
# second aws_iam_openid_connect_provider resource for the same URL would
# conflict in AWS.
#
# Trust is scoped to this specific repo AND to the main branch
# (ref:refs/heads/main) - every terraform-*.yaml workflow only triggers on
# push to main, so nothing legitimate needs this role from any other ref.
# Permission-wise this is intentionally broad (AdministratorAccess): this
# repo's Terraform creates and modifies IAM roles/policies for EKS, Lambda,
# Pod Identity, etc. across nearly every AWS service in play, which
# inherently requires broad rights (iam:CreateRole, iam:PassRole, and
# service-specific create/modify/delete across EC2, EKS, RDS, ElastiCache,
# DynamoDB, SQS, Lambda, CloudFormation, SecretsManager, ECR, S3, AMP/AMG).
# The actual security boundary here is: no more long-lived leakable keys,
# the repo+branch trust condition below, and the existing manual-approval
# GitHub Environments gating every apply job.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions_terraform" {
  name = "github-actions-terraform-role-gleamgoods-devops"

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
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:dercioanselmo/GleamGoods-DevOps:ref:refs/heads/main"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "github_actions_terraform_admin" {
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "github_actions_terraform_role_arn" {
  description = "IAM Role ARN GitHub Actions assumes (via OIDC) for every terraform-*.yaml workflow in every CI-applied module in this repo"
  value       = aws_iam_role.github_actions_terraform.arn
}
