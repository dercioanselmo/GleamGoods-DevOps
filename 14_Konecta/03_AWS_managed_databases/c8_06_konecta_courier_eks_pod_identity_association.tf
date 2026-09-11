################################################################################
# EKS Pod Identity Association - Konecta Courier
################################################################################

# Allows the Konecta Courier microservice (ServiceAccount `courier` in
# the `konecta` namespace) to assume the shared IAM role that has access
# to the Konecta DB secret in AWS Secrets Manager, so the Secrets Store
# CSI Driver can mount it into the Courier Pod at runtime.

resource "aws_eks_pod_identity_association" "konecta_courier" {
  cluster_name    = data.terraform_remote_state.eks.outputs.eks_cluster_name
  namespace       = "konecta"
  service_account = "courier"
  role_arn        = aws_iam_role.konecta_getsecrets.arn
}

output "konecta_courier_sa_pod_identity_association_arn" {
  description = "Pod Identity Association ARN for the Konecta Courier ServiceAccount"
  value       = aws_eks_pod_identity_association.konecta_courier.association_arn
}
