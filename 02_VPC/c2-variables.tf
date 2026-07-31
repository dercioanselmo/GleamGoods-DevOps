variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used in resource names and tags"
  type        = string
  default     = "gleamgoods"
}
// Defines overall IP address range. /16 - 65000 Addresses when dealing with /16
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "tags" {
  description = "Global tags to apply to all resources"
  type        = map(string)
  default     = {
    Terraform = "true"
  }
}
// Defines how many new bits to add to the VPC CIDR to generate subnets. For example, 8 means /24 subnets from a /16 VPC.
// Tells terraform how to split VPC CIDR 
// Each subnet will have 256 addresses. 2 are reserved for network and broadcast, leaving 254 usable addresses per subnet.
variable "subnet_newbits" {
  description = "Number of new bits to add to VPC CIDR to generate subnets (e.g., 8 means /24 from /16)"
  type        = number
  default     = 8
}