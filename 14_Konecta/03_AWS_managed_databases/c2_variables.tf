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
  default     = "konecta"
}

# Business unit or department (used in tags and naming)
variable "business_division" {
  description = "Business Division in the large organization this infrastructure belongs to"
  type        = string
  default     = "retail"
}

# --------------------------------------------------------
# Secrets Manager
# --------------------------------------------------------

variable "konecta_db_secret_name" {
  description = "AWS Secrets Manager secret name for the shared Konecta RDS PostgreSQL master credentials (used only to set each aws_db_instance's master username/password - never mounted to application pods, never itself rotated)"
  type        = string
  default     = "konecta-db-secret"
}

variable "konecta_db_username" {
  description = "Master username stored in konecta-db-secret and used by every Konecta RDS PostgreSQL instance"
  type        = string
  default     = "konecta_admin"
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
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Terraform = "true"
  }
}
