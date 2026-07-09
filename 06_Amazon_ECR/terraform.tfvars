aws_region    = "us-east-1"
project_name  = "gleamgoods"

github_repo  = "dercioanselmo/GleamGoods"
role_name    = "github-actions-oidc-role-gleamgoods"

tags = {
  Terraform   = "true"
  Environment = "gleamgoods"
  Project     = "GleamGoods"
  ManagedBy   = "platform-team"
}