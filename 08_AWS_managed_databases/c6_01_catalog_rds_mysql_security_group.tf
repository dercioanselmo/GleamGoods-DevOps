# Security Group for RDS MySQL
resource "aws_security_group" "rds_mysql_sg" {
  name        = "${local.name}-rds-mysql-sg"
  description = "Allow MySQL access from EKS cluster"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description = "Allow MySQL from EKS cluster security group"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [
      data.terraform_remote_state.eks.outputs.eks_cluster_security_group_id
    ]
  }

  # Kept inline (rather than a separate aws_security_group_rule) because this
  # resource already manages its ingress set via inline blocks - mixing the
  # two models causes Terraform to treat itself as authoritative and revoke
  # any rule added by a standalone aws_security_group_rule on the next apply.
  ingress {
    description     = "Allow Catalog rotation Lambda"
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups  = [aws_security_group.catalog_rotation_lambda_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-rds-mysql-sg"
  }
}