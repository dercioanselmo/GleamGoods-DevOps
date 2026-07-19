# Security Group for RDS PostgreSQL
# Allow access only from EKS Cluster security group
resource "aws_security_group" "rds_postgresql_sg" {
  name        = "${local.name}-rds-postgresql-sg"
  description = "Allow RDS PostgreSQL access from EKS cluster"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description      = "Allow RDS PostgreSQL from EKS Cluster"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    security_groups  = [data.terraform_remote_state.eks.outputs.eks_cluster_security_group_id]
  }

  # Kept inline (rather than a separate aws_security_group_rule) because this
  # resource already manages its ingress set via inline blocks - mixing the
  # two models causes Terraform to treat itself as authoritative and revoke
  # any rule added by a standalone aws_security_group_rule on the next apply.
  ingress {
    description      = "Allow Orders rotation Lambda"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    security_groups  = [aws_security_group.orders_rotation_lambda_sg.id]
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
