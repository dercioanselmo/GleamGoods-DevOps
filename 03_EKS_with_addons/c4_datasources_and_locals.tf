# --------------------------------------------------------------------
# Local values used throughout the EKS configuration
# Helps enforce naming consistency and reduce duplication
# --------------------------------------------------------------------
locals {
  # Business division or team name (from variable)
  owners = var.business_division  # Example: "retail"

  # Environment name such as dev, staging, prod (from variable)
  environment = var.project_name  # Example: "gleamgoods"

  # Standardized naming prefix: "<division>-<project>"
  name = "${local.owners}-${local.environment}"  # Example: "retail-gleamgoods"

  # Full EKS cluster name used for resource naming and tagging
  eks_cluster_name = "${local.name}-${var.cluster_name}"  # Example: "retail-gleamgoods-eks"
}