output "ecr_repository_urls" {
  description = "Map of ECR Repository URLs"
  value = {
    for k, v in aws_ecr_repository.ecr : k => v.repository_url
  }
}

output "ecr_repository_arns" {
  description = "Map of ECR Repository ARNs"
  value = {
    for k, v in aws_ecr_repository.ecr : k => v.arn
  }
}

output "github_oidc_role_arn" {
  description = "IAM Role ARN used by GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "github_oidc_role_name" {
  value = aws_iam_role.github_actions.name
}
