##############################################
# Discover default/latest ExternalDNS addon versions (informational only -
# see var.addon_versions in c2-variables.tf for what's actually applied)
##############################################
data "aws_eks_addon_version" "externaldns_default" {
  addon_name         = "external-dns"
  kubernetes_version = aws_eks_cluster.main.version
}

data "aws_eks_addon_version" "externaldns_latest" {
  addon_name         = "external-dns"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

##############################################
# Install ExternalDNS Add-on
##############################################
resource "aws_eks_addon" "externaldns" {
  depends_on = [aws_eks_node_group.private_nodes]
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "external-dns"
  # Pinned - see var.addon_versions in c2-variables.tf. The data sources
  # above are kept only so their outputs show when a newer version becomes
  # available; they no longer drive this value.
  addon_version               = var.addon_versions.external_dns

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  service_account_role_arn = aws_iam_role.externaldns_role.arn

  tags = {
    Component   = "ExternalDNS"
    ManagedBy   = "Terraform"
    Project     = local.name
  }
}

##############################################
# Outputs
##############################################
output "externaldns_addon_version" {
  value = aws_eks_addon.externaldns.addon_version
}

output "externaldns_addon_default_version" {
  value = data.aws_eks_addon_version.externaldns_default.version
}

output "externaldns_addon_latest_version" {
  value = data.aws_eks_addon_version.externaldns_latest.version
}

output "externaldns_addon_arn" {
  value = aws_eks_addon.externaldns.arn
}

output "externaldns_addon_id" {
  value = aws_eks_addon.externaldns.id
}