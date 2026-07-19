# Install Stakater Reloader
#
# Watches ConfigMaps/Secrets and triggers a rolling restart of any
# Deployment/StatefulSet/Rollout annotated with
# reloader.stakater.com/auto: "true" when the referenced object's data
# changes. Used to auto-refresh Catalog/Orders pods after the Secrets
# Store CSI driver syncs a rotated DB credential into the catalog-db /
# orders-db Kubernetes Secrets - closes the loop between "Secrets Manager
# rotated the password" and "the running pod picks it up" without any
# custom EventBridge/Lambda-to-cluster glue.
resource "helm_release" "reloader" {
  depends_on = [
    aws_eks_node_group.private_nodes
  ]

  name       = "reloader"
  repository = "https://stakater.github.io/stakater-charts"
  chart      = "reloader"
  namespace  = "kube-system"

  set = [
    {
      # Enables restart support for argoproj.io Rollout objects (Orders
      # uses a Rollout, not a plain Deployment), in addition to the
      # Deployments/StatefulSets/DaemonSets Reloader already watches.
      name  = "reloader.isArgoRollouts"
      value = "true"
    }
  ]

  wait            = true
  timeout         = 600
  cleanup_on_fail = true
}

output "helm_reloader_metadata" {
  description = "Metadata for the Stakater Reloader Helm release"
  value       = helm_release.reloader.metadata
}
