################################################################################
# EKS Pod Identity Association - Konecta Checkout
################################################################################

# Allows the Konecta Checkout microservice (ServiceAccount `checkout` in
# the `konecta` namespace) to assume the shared IAM role that has access
# to the Konecta DB secret in AWS Secrets Manager, so the Secrets Store
# CSI Driver can mount it into the Checkout Pod at runtime.

resource "aws_eks_pod_identity_association" "konecta_checkout" {
  cluster_name    = data.terraform_remote_state.eks.outputs.eks_cluster_name
  namespace       = "konecta"
  service_account = "checkout"
  role_arn        = aws_iam_role.konecta_getsecrets.arn
}

output "konecta_checkout_sa_pod_identity_association_arn" {
  description = "Pod Identity Association ARN for the Konecta Checkout ServiceAccount"
  value       = aws_eks_pod_identity_association.konecta_checkout.association_arn
}
