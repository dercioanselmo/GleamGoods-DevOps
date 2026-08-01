# --------------------------------------------------------------------
# VPC CNI - adopted as a Terraform-managed EKS addon to enable native
# NetworkPolicy enforcement
# --------------------------------------------------------------------
#
# This is the correct place for the "enable NetworkPolicy enforcement"
# change discussed in 13_RBAC_NetworkPolicy/README.md - it's an EKS addon
# configuration value (enableNetworkPolicy), not a node group setting.
# aws_eks_node_group has no equivalent field; the node group's IAM role
# (c8_eks_nodegroup_iamrole.tf) already has AmazonEKS_CNI_Policy attached,
# which is everything the network policy agent needs - no node group or
# IAM changes required alongside this file. Nodes already run AL2023
# (var.node_ami_type default), which is kernel-compatible with the policy
# agent's eBPF requirements.
#
# resolve_conflicts_on_create = "OVERWRITE" is required here specifically
# (more so than on this project's other addons) because this is adopting
# an addon that's already running unmanaged - without OVERWRITE, Terraform
# would fail trying to install "over" the existing self-managed vpc-cni.

data "aws_eks_addon_version" "vpccni_default" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.main.version
}

data "aws_eks_addon_version" "vpccni_latest" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

resource "aws_eks_addon" "vpc_cni" {
  depends_on = [aws_eks_node_group.private_nodes]

  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  # Pinned - see var.addon_versions in c2-variables.tf. The data sources
  # above are kept only so their outputs show when a newer version becomes
  # available; they no longer drive this value.
  addon_version = var.addon_versions.vpc_cni

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  tags = {
    Component = "VPC-CNI"
    ManagedBy = "Terraform"
    Project   = local.name
  }
}

##############################################
# Outputs
##############################################
output "vpccni_addon_version" {
  value = aws_eks_addon.vpc_cni.addon_version
}

output "vpccni_addon_default_version" {
  value = data.aws_eks_addon_version.vpccni_default.version
}

output "vpccni_addon_latest_version" {
  value = data.aws_eks_addon_version.vpccni_latest.version
}

output "vpccni_addon_arn" {
  value = aws_eks_addon.vpc_cni.arn
}
