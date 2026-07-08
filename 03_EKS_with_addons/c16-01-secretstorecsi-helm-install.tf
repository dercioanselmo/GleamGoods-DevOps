# Install Secrets Store CSI Driver (Kubernetes SIGs)
resource "helm_release" "secrets_store_csi_driver" {
  depends_on = [
    aws_eks_addon.podidentity,
    aws_eks_node_group.private_nodes
  ]

  name       = "csi-secrets-store"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"

  set = [
    {
      name  = "syncSecret.enabled"
      value = "true"
    },

    # Fix the error: This error was noticed when creating the catalog pods in the EKS cluster
    # MountVolume.SetUp failed for volume "aws-secrets" : rpc error: code = Unknown desc = failed to mount secrets store objects for pod default/catalog-7b55c467cb-m54gr, err: rpc error: code = Unknown desc = Pod Identity token extraction failed: token for audience "pods.eks.amazonaws.com" not found - ensure tokenRequests includes this audience in CSIDriver
    {
      name  = "tokenRequests[0].audience"
      value = "pods.eks.amazonaws.com"
    }
    #The fix end here
  ]

 # Wait until all pods are ready
  wait            = true
  timeout         = 600
  cleanup_on_fail = true
}

# Outputs

output "helm_secrets_store_csi_driver_metadata" {
  description = "Metadata for the Secrets Store CSI Driver Helm release"
  value       = helm_release.secrets_store_csi_driver.metadata
}