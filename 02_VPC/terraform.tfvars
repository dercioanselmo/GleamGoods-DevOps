# Environment & Region for Development
project_name = "gleamgoods"
aws_region       = "us-east-1"

# CIDR for VPC
vpc_cidr = "10.0.0.0/16"

# Subnet mask (/24 subnets)
subnet_newbits = 8

# Fake secret to test Trivy secret scanning
aws_secret_access_key = "kR8vN2pL9mX4qT7wY1uZ3sA6dF0jH5cB8eG2iK4"

# Tags for Dev Environment
tags = {
  Terraform   = "true"
  Project     = "retail-store"
  Owner       = "Dercio Anselmo"
}