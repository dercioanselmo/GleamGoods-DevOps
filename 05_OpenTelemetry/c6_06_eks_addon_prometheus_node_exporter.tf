# Datasource: To get default EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "prometheus_node_exporter_default" {
  addon_name         = "prometheus-node-exporter"
  kubernetes_version = data.terraform_remote_state.eks.outputs.eks_cluster_version
}

# Datasource: To get latest EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "prometheus_node_exporter_latest" {
  addon_name         = "prometheus-node-exporter"
  kubernetes_version = data.terraform_remote_state.eks.outputs.eks_cluster_version
  most_recent        = true
}

# EKS Add-on: Prometheus Node Exporter 
resource "aws_eks_addon" "prometheus_node_exporter" {
  cluster_name  = data.terraform_remote_state.eks.outputs.eks_cluster_id
  addon_name    = "prometheus-node-exporter"
  # Pinned - see var.addon_versions in c2_variables.tf. The _default/_latest
  # data sources above are kept only so their outputs show when a newer
  # version becomes available; they no longer drive this value.
  addon_version = var.addon_versions.prometheus_node_exporter
  # Conflict resolution
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags = var.tags
}


# Outputs
output "prometheus_node_exporter_addon_id" {
  description = "Prometheus Node Exporter EKS Addon ID"
  value       = aws_eks_addon.prometheus_node_exporter.id
}

output "prometheus_node_exporter_addon_version" {
  description = "Prometheus Node Exporter EKS Addon Version"
  value       = aws_eks_addon.prometheus_node_exporter.addon_version
}