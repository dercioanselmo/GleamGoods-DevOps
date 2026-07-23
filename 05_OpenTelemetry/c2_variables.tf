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

# --------------------------------------------------------
# Common Tags
# --------------------------------------------------------

# Tags applied to all resources created by this configuration
variable "tags" {
  description = "Tags to apply to EKS and related resources"
  type        = map(string)
  default     = {
    Terraform = "true"
  }
}

# --------------------------------------------------------
# EKS Addon Versions (pinned - see addon .tf files)
# --------------------------------------------------------

# Explicit, pinned versions for every aws_eks_addon in this module. Nothing
# here moves on its own - bump a value deliberately when you want that addon
# to upgrade. Each *_default/*_latest data source pair (in the addon's own
# .tf file) is kept purely for visibility (their outputs tell you when a
# newer version exists) and no longer drives what actually gets installed.
# Defaults below match what's live as of the day this was pinned, so
# applying this change alone is a no-op. Same pattern as
# 03_EKS_with_addons/c2-variables.tf's addon_versions.
variable "addon_versions" {
  description = "Pinned EKS addon versions for this cluster's Kubernetes version. Bump deliberately when upgrading."
  type = object({
    adot                     = string
    cert_manager             = string
    kube_state_metrics       = string
    prometheus_node_exporter = string
  })
  default = {
    adot                     = "v0.151.0-eksbuild.2"
    cert_manager             = "v1.21.0-eksbuild.2"
    kube_state_metrics       = "v2.19.1-eksbuild.2"
    prometheus_node_exporter = "v1.11.1-eksbuild.7"
  }
}



