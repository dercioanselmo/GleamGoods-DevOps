# Project & Region 
project_name = "gleamgoods"
aws_region       = "us-east-1"

# CIDR for VPC
vpc_cidr = "10.0.0.0/16"

# Subnet mask (/24 subnets)
subnet_newbits = 8

# Tags for Dev Environment
tags = {
  Terraform   = "true"
  Project     = "GleamGoods"
  Owner       = "Dercio Anselmo"
}