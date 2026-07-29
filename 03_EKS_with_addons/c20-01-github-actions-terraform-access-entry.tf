# --------------------------------------------------------------------
# EKS cluster access for the GitHub Actions Terraform CI role
# --------------------------------------------------------------------
# aws_iam_role.github_actions_terraform (01_remote_backend_s3bucket) has
# AdministratorAccess on the AWS side, but that's a separate concern from
# Kubernetes RBAC - the EKS API server checks its own access mapping
# (Access Entries / aws-auth ConfigMap) before honoring any kubectl-style
# request, regardless of what IAM permissions the caller has.
#
# bootstrap_cluster_creator_admin_permissions (c7_eks_cluster.tf) only
# grants cluster-admin to whichever identity ran terraform apply at the
# moment the cluster was CREATED - that was a human's local AWS identity,
# not this role, which didn't exist yet at that point. Without this access
# entry, any `kubernetes_*` Terraform resource (e.g. c6_09 in
# 05_OpenTelemetry: kubernetes_service_account_v1, kubernetes_cluster_role_v1)
# fails with "Unauthorized" the moment CI tries to apply it, even though
# every AWS-API resource in the same plan succeeds fine.
#
# The role lives in a different Terraform module (01_remote_backend_s3bucket)
# using local state, so its ARN can't be pulled via data.terraform_remote_state
# the way this project does for S3-backed modules - hardcoded here instead,
# matching the same static-ARN pattern already used for this exact role in
# every .github/workflows/terraform-*.yaml file's role-to-assume.
resource "aws_eks_access_entry" "github_actions_terraform" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::564956047797:role/github-actions-terraform-role-gleamgoods-devops"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions_terraform_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.github_actions_terraform.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
