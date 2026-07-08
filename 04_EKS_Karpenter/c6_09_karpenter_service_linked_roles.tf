# c6_09_karpenter_service_linked_roles.tf

# =============================================================================
# EC2 Spot Service-Linked Role (AWSServiceRoleForEC2Spot)
# Required for Karpenter to launch Spot instances via CreateFleet
# =============================================================================

resource "aws_iam_service_linked_role" "ec2_spot" {
  aws_service_name = "spot.amazonaws.com"
  description      = "Service-linked role for EC2 Spot Instances used by Karpenter"

  # This resource is idempotent — if the role already exists, Terraform will just manage it
}

resource "aws_iam_service_linked_role" "ec2_spot_fleet" {
  aws_service_name = "spotfleet.amazonaws.com"
  description      = "Service-linked role for EC2 Spot Fleet"
}

# Output for visibility
output "ec2_spot_service_linked_role_name" {
  description = "Name of the EC2 Spot Service-Linked Role"
  value       = aws_iam_service_linked_role.ec2_spot.name
}

output "ec2_spot_service_linked_role_arn" {
  description = "ARN of the EC2 Spot Service-Linked Role"
  value       = aws_iam_service_linked_role.ec2_spot.arn
}