# Security Group for the Konecta RDS PostgreSQL instances
# Shared by all 5 Konecta databases - allow access only from the EKS Cluster security group
resource "aws_security_group" "konecta_rds_postgresql_sg" {
  name        = "${local.name}-rds-postgresql-sg"
  description = "Allow Konecta RDS PostgreSQL access from EKS cluster"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description     = "Allow RDS PostgreSQL from EKS Cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.eks.outputs.eks_cluster_security_group_id]
  }

  # One rule per database's rotation Lambda SG (c9_02). Kept as dynamic
  # inline blocks on this same resource - rather than separate
  # aws_security_group_rule resources - because this resource already
  # manages its ingress set via inline blocks; mixing the two models
  # causes Terraform to treat itself as authoritative and revoke any rule
  # added by a standalone aws_security_group_rule on the next apply. Same
  # gotcha documented in 08_AWS_managed_databases for its own
  # rotation-Lambda ingress rules.
  dynamic "ingress" {
    for_each = aws_security_group.konecta_rotation_lambda_sg
    content {
      description     = "Allow Konecta ${ingress.key} rotation Lambda"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value.id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-rds-postgresql-sg"
  }
}
