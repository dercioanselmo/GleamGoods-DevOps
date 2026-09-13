################################################################################
# EKS Pod Identity Association - Konecta Cart
################################################################################

# Allows the Konecta Cart microservice (ServiceAccount `cart` in the
# `konecta` namespace) to assume its own dedicated IAM role, scoped only
# to the Cart database's own app secret, so the Secrets Store CSI Driver
# can mount it into the Cart Pod at runtime.

resource "aws_eks_pod_identity_association" "konecta_cart" {
  cluster_name    = data.terraform_remote_state.eks.outputs.eks_cluster_name
  namespace       = "konecta"
  service_account = "cart"
  role_arn        = aws_iam_role.konecta_getsecrets["cart"].arn
}

output "konecta_cart_sa_pod_identity_association_arn" {
  description = "Pod Identity Association ARN for the Konecta Cart ServiceAccount"
  value       = aws_eks_pod_identity_association.konecta_cart.association_arn
}
