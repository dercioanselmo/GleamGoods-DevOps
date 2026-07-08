# EKS Managed Node Group - Private Subnets
resource "aws_eks_node_group" "private_nodes" {

  # The name of the EKS cluster this node group belongs to
  cluster_name = aws_eks_cluster.main.name

  # Logical name for this node group in the EKS cluster
  node_group_name = "${local.name}-private-ng"

  # IAM role that EC2 worker nodes will assume
  node_role_arn = aws_iam_role.eks_nodegroup_role.arn

  # Subnets where the worker nodes will be launched (typically private subnets)
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  # Instance types for the nodes (e.g., t3.medium, m5.large)
  instance_types = var.node_instance_types

  # Choose between ON_DEMAND or SPOT capacity types
  capacity_type = var.node_capacity_type

  # Use Amazon Linux 2023 AMI — the latest Amazon-managed OS optimized for EKS
  # Fully supported in Kubernetes v1.25+ and production-ready
  # Better security, updated packages, and long-term support (recommended over AL2)
  ami_type = var.node_ami_type

  disk_size = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable_percentage = var.node_max_unavailable_percentage
  }

  force_update_version = var.node_force_update_version

  # Apply labels to each EC2 instance for easier scheduling and management in Kubernetes
  labels = {
    "project" = var.project_name
    "team"    = var.business_division
  }

  tags = merge(var.tags, {
    Name        = "${local.name}-private-ng"
    Environment = var.project_name
  })

  # Ensure IAM role policies are attached before creating the node group
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy
  ]
}