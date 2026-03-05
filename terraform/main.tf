# =====================================================
# Tetris - High Availability AWS Infrastructure
# =====================================================
# Architecture:
#   Internet → ALB (multi-AZ, managed) → EKS Node Groups
#              (on-demand + spot, 3 AZs)
#
# No EC2 bastion. Cluster access via:
#   - kubectl through EKS public endpoint
#
# Modules: vpc · iam · eks · alb
# =====================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  required_version = ">= 1.6"

  backend "s3" {
    bucket         = "oneclick-8828-1689-7263"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    # dynamodb_table = "oneclick-locks"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ===== VPC =====
module "vpc" {
  source = "./modules/vpc"

  name         = var.name
  environment  = var.environment
  cluster_name = var.cluster_name
  cidr_block   = var.cidr_block
}

# ===== IAM =====
module "iam" {
  source = "./modules/iam"

  cluster_name = var.cluster_name
  environment  = var.environment
}

# ===== EKS =====
module "eks" {
  source = "./modules/eks"

  cluster_name         = var.cluster_name
  environment          = var.environment
  private_subnet_ids   = module.vpc.private_subnet_ids
  eks_cluster_role_arn = module.iam.eks_cluster_role_arn
  eks_nodes_role_arn   = module.iam.eks_nodes_role_arn
  eks_cluster_sg_id    = module.vpc.eks_cluster_sg_id
  public_access_cidrs  = var.public_access_cidrs
}

# ===== ALB =====
module "alb" {
  source = "./modules/alb"

  name              = var.name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.vpc.alb_sg_id
}
