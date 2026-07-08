module "vpc" {
  source       = "./modules/vpc"
  project_name = var.project_name
  vpc_cidr       = var.vpc_cidr
  subnet_newbits = var.subnet_newbits
  tags           = var.tags
}