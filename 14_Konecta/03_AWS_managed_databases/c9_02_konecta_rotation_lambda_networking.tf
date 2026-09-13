# --------------------------------------------------------------------
# Networking for the Konecta Secrets Manager rotation Lambdas
# --------------------------------------------------------------------
# RDS is private (publicly_accessible = false), so each rotation Lambda
# must run inside the VPC to reach its database. Each database gets its
# own security group, matching 08_AWS_managed_databases: the blast
# radius of one Lambda's network access stays scoped to its own DB.

resource "aws_security_group" "konecta_rotation_lambda_sg" {
  for_each = local.konecta_service_keys

  name        = "${local.name}-${each.key}-rotation-lambda-sg"
  description = "Secrets Manager rotation Lambda for Konecta ${each.key} PostgreSQL"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  egress {
    description = "Allow all egress (PostgreSQL to RDS, HTTPS to Secrets Manager endpoint)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-${each.key}-rotation-lambda-sg"
  }
}

# The RDS-side ingress rules allowing these Lambda SGs in are declared
# inline on aws_security_group.konecta_rds_postgresql_sg (c7_01) rather
# than here as separate aws_security_group_rule resources - see the
# comment there for why mixing the two models is unsafe.
