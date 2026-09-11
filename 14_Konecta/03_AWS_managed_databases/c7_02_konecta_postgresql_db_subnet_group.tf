# RDS PostgreSQL Database Subnet Group - shared by all 5 Konecta databases
resource "aws_db_subnet_group" "konecta_rds_postgresql_subnet_group" {
  name        = "${local.name}-rds-postgresql-subnet-group"
  description = "Subnet group for Konecta RDS PostgreSQL databases"
  subnet_ids  = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  tags = {
    Name = "${local.name}-rds-postgresql-subnet-group"
  }
}
