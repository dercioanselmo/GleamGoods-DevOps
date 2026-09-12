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
  description = "AWS Secrets Manager secret name for the shared Konecta RDS PostgreSQL credentials (used as master username/password for every Konecta database, and mounted to every Konecta service pod via Secrets Store CSI Driver)"
  type        = string
  default     = "konecta-db-secret"
}

variable "konecta_db_username" {
  description = "Master username stored in konecta-db-secret and used by every Konecta RDS PostgreSQL instance"
  type        = string
  default     = "konecta_admin"
}

# Tags applied to all resources created by this configuration
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Terraform = "true"
  }
}
