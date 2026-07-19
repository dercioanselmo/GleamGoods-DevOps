# --------------------------------------------------------------------
# Networking for the Secrets Manager rotation Lambdas
# --------------------------------------------------------------------
# RDS is private (publicly_accessible = false), so the rotation Lambdas must
# run inside the VPC to reach it. Each gets its own security group so the
# blast radius of one Lambda's network access stays scoped to its own DB.

resource "aws_security_group" "catalog_rotation_lambda_sg" {
  name        = "${local.name}-catalog-rotation-lambda-sg"
  description = "Secrets Manager rotation Lambda for Catalog MySQL"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  egress {
    description = "Allow all egress (MySQL to RDS, HTTPS to Secrets Manager endpoint)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-catalog-rotation-lambda-sg"
  }
}

resource "aws_security_group" "orders_rotation_lambda_sg" {
  name        = "${local.name}-orders-rotation-lambda-sg"
  description = "Secrets Manager rotation Lambda for Orders PostgreSQL"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  egress {
    description = "Allow all egress (PostgreSQL to RDS, HTTPS to Secrets Manager endpoint)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-orders-rotation-lambda-sg"
  }
}

# Allow each rotation Lambda into its own database only.
resource "aws_security_group_rule" "rds_mysql_from_catalog_rotation_lambda" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_mysql_sg.id
  source_security_group_id = aws_security_group.catalog_rotation_lambda_sg.id
  description              = "Allow Catalog rotation Lambda"
}

resource "aws_security_group_rule" "rds_postgresql_from_orders_rotation_lambda" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_postgresql_sg.id
  source_security_group_id = aws_security_group.orders_rotation_lambda_sg.id
  description              = "Allow Orders rotation Lambda"
}
