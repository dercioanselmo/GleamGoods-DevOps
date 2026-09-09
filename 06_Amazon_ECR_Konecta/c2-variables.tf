variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repository (owner/repo)"
  type        = string
  default     = "dercioanselmo/GleamGoods"
}

variable "role_name" {
  description = "IAM Role name for GitHub Actions"
  type        = string
  default     = "github-actions-oidc-role-gleamgoods"
}

variable "project_name" {
  description = "Project name used in resource names and tags"
  type        = string
  default     = "gleamgoods"
}

variable "tags" {
  description = "Global tags to apply to all resources"
  type        = map(string)
  default     = {
    Terraform = "true"
  }
}

# List of all ECR repositories to create
variable "ecr_repositories" {
  description = "List of ECR repositories to create"
  type        = list(string)
  default = [
    "gleamgoods/ui",
    "gleamgoods/cart",
    "gleamgoods/catalog",
    "gleamgoods/checkout",
    "gleamgoods/orders"
  ]
}