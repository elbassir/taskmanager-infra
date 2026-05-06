# ============================================================
# Versions & Provider Configuration — TaskManager PFE DevOps
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# AWS Provider — région Paris (eu-west-3)
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "taskmanager"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "pfe-devops"
    }
  }
}

# Kubernetes Provider — pointe sur le cluster EKS créé
provider "kubernetes" {
  host                   = module.eks_cluster.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.eks_cluster_ca)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Helm Provider — pour déployer des charts sur EKS
provider "helm" {
  kubernetes {
    host                   = module.eks_cluster.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.eks_cluster_ca)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Auth token pour kubectl / helm
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks_cluster.eks_cluster_name
}
