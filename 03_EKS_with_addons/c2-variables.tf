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
# EKS Cluster Configuration
# --------------------------------------------------------

# Name of the EKS cluster (used in names, tags, and references)
variable "cluster_name" {
  description = "Name of the EKS cluster. Also used as a prefix in names of related resources."
  type        = string
  default     = "eks"
}

# Kubernetes version for the EKS control plane
variable "cluster_version" {
  description = "Kubernetes minor version to use for the EKS cluster (e.g. 1.28, 1.29)"
  type        = string
  default     = null
}

# CIDR block used for Kubernetes service networking
variable "cluster_service_ipv4_cidr" {
  description = "Service CIDR range for Kubernetes services. Optional — leave null to use AWS default."
  type        = string
  default     = null
}

# Enable access to the EKS API via private endpoint
variable "cluster_endpoint_private_access" {
  description = "Whether to enable private access to EKS control plane endpoint"
  type        = bool
  default     = false
}

# Enable access to the EKS API via public endpoint
variable "cluster_endpoint_public_access" {
  description = "Whether to enable public access to EKS control plane endpoint"
  type        = bool
  default     = true
}

# List of CIDRs allowed to reach the public EKS API endpoint
variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks allowed to access public EKS endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
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
# EKS Node Group Configuration
# --------------------------------------------------------

variable "node_instance_types" {
  description = "List of EC2 instance types for the node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Instance capacity type: ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_disk_size" {
  description = "Disk size in GiB for worker nodes"
  type        = number
  default     = 20
}

variable "node_ami_type" {
  description = "AMI type for worker nodes (e.g. AL2023_x86_64_STANDARD, AL2_x86_64)"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 6
}

variable "node_max_unavailable_percentage" {
  description = "Max percentage of nodes unavailable during node group update"
  type        = number
  default     = 33
}

variable "node_force_update_version" {
  description = "Force node group update when EKS AMI version changes"
  type        = bool
  default     = true
}

# --------------------------------------------------------
# EKS Cluster Access & Logging
# --------------------------------------------------------

variable "cluster_authentication_mode" {
  description = "Authentication mode for EKS cluster: CONFIG_MAP, API, or API_AND_CONFIG_MAP"
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "cluster_bootstrap_admin_permissions" {
  description = "Grant cluster-admin permissions to the cluster creator"
  type        = bool
  default     = true
}

variable "cluster_log_types" {
  description = "List of EKS control plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}
