# --------------------------------------------------------
# AWS Region (used in provider block)
# --------------------------------------------------------
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_region_remote_state" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# --------------------------------------------------------
# Environment & Business Division Info
# --------------------------------------------------------

# Logical environment name (used in tags and resource names)
variable "project_name" {
  description = "Project name used in resource names and tags"
  type        = string
  default     = "gleamgoods"
}

# Business unit or department (used in tags and naming)
variable "business_division" {
  description = "Business Division in the large organization this infrastructure belongs to"
  type        = string
  default     = "retail"
}

variable "db_secret_name" {
  description = "AWS Secrets Manager secret name for the shared RDS master credentials (used only to set aws_db_instance master username/password and as the rotation Lambdas' masterarn - never mounted to application pods)"
  type        = string
  default     = "gleamgoods-db-secret"
}

variable "catalog_db_secret_name" {
  description = "AWS Secrets Manager secret name for the Catalog app's dedicated, auto-rotated MySQL user"
  type        = string
  default     = "gleamgoods-catalog-db-secret"
}

variable "orders_db_secret_name" {
  description = "AWS Secrets Manager secret name for the Orders app's dedicated, auto-rotated PostgreSQL user"
  type        = string
  default     = "gleamgoods-orders-db-secret"
}

variable "rotation_days" {
  description = "Number of days between automatic secret rotations"
  type        = number
  default     = 30
}

variable "sar_publisher_account_id" {
  description = "AWS account ID that publishes the Secrets Manager RDS rotation apps to the Serverless Application Repository (AWS-owned, not this project's account)"
  type        = string
  default     = "297356227824"
}

# Tags applied to all resources created by this configuration
variable "tags" {
  description = "Tags to apply to EKS and related resources"
  type        = map(string)
  default = {
    Terraform = "true"
  }
}