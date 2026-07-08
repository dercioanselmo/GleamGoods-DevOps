terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.20"
    }

    helm = {
      source  = "hashicorp/helm"
      #version = ">= 3.0"
      version = "~> 3.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.28"
    }
  }


  # Remote backend configuration using S3 
  backend "s3" {
    bucket         = "tfstate-dev-us-east-1-1v8wcs"       
    key            = "karpenter/gleamgoods/terraform.tfstate"            
    region         = "us-east-1"                            
    encrypt        = true                                   
    use_lockfile   = true     
  }
}

provider "aws" {
  # AWS region to use for all resources (from variables)
  region = var.aws_region
}

# Required for public ECR authorization token
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}