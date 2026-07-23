# Datasource: To get default EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "metrics_server_default" {
  addon_name         = "metrics-server"
  kubernetes_version = aws_eks_cluster.main.version
}
 
# Datasource: To get latest EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "metrics_server_latest" {
  addon_name         = "metrics-server"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

# EKS Addon: Pod Identity Agent
resource "aws_eks_addon" "metrics_server" {
  depends_on = [aws_eks_node_group.private_nodes]  
  cluster_name                = aws_eks_cluster.main.id
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  # Pinned - see var.addon_versions in c2-variables.tf. The _default/_latest
  # data sources above are kept only so their outputs show when a newer
  # version becomes available; they no longer drive this value.
  addon_version               = var.addon_versions.metrics_server
}


# Outputs
output "metrics_server_eksaddon_default_version" {
  value = data.aws_eks_addon_version.metrics_server_default.version
}

output "metrics_server_eksaddon_lastest_version" {
  value = data.aws_eks_addon_version.metrics_server_latest.version
}

output "metrics_server_agent_eksaddon_arn" {
  value = aws_eks_addon.metrics_server.arn
}  

output "metrics_server_agent_eksaddon_id" {
  value = aws_eks_addon.metrics_server.id
}