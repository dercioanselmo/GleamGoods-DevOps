################################################################################
# EKS Pod Identity Association - Konecta Store Stock
################################################################################

# Allows the Konecta Store Stock microservice (ServiceAccount
# `store-stock` in the `konecta` namespace) to assume its own dedicated
# IAM role, scoped only to the Store Stock database's own app secret, so
# the Secrets Store CSI Driver can mount it into the Store Stock Pod at
# runtime.

resource "aws_eks_pod_identity_association" "konecta_store_stock" {
  cluster_name    = data.terraform_remote_state.eks.outputs.eks_cluster_name
  namespace       = "konecta"
  service_account = "store-stock"
  role_arn        = aws_iam_role.konecta_getsecrets["store_stock"].arn
}

output "konecta_store_stock_sa_pod_identity_association_arn" {
  description = "Pod Identity Association ARN for the Konecta Store Stock ServiceAccount"
  value       = aws_eks_pod_identity_association.konecta_store_stock.association_arn
}
