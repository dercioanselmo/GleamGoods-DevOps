# Environment & Region for Development
project_name = "gleamgoods"
aws_region       = "us-east-1"

# CIDR for VPC
vpc_cidr = "10.0.0.0/16"

# Subnet mask (/24 subnets)
subnet_newbits = 8

# Fake secret to test Trivy secret scanning - DO NOT COMMIT REAL SECRETS
AWS_ACCESS_KEY_ID = "AKIAIOSFODNN7TESTKEY"
aws_secret_access_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYTESTKEY12"

# Tags for Dev Environment
tags = {
  Terraform   = "true"
  Project     = "retail-store"
  Owner       = "Dercio Anselmo"
}