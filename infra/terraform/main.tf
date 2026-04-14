# ============================================================
# main.tf — Infrastructure TaskManager PFE DevOps
# Inspiré de spring-petclinic-infra-aws-terraform
# Architecture : VPC → EKS Cluster → Node Group → RDS PostgreSQL
# ============================================================

# ---- Module VPC ----
module "aws_vpc" {
  source = "./modules/vpc"

  vpc_cidr             = var.vpc_cidr
  environment          = var.environment
  azs                  = local.availability_zones
  public_subnets_cidr  = var.public_subnets_cidr
  private_subnets_cidr = var.private_subnets_cidr
}

# ---- Module EKS Cluster ----
module "eks_cluster" {
  source = "./modules/eks-cluster"

  cluster_config = {
    name    = "eks-cluster-taskmanager"
    version = var.eks_version
  }

  public_subnets_ids  = module.aws_vpc.public_subnets_ids
  private_subnets_ids = module.aws_vpc.private_subnets_ids
  resource_name_prefix = "taskmanager-"
}

# ---- Module EKS Node Group ----
module "eks_nodegroup" {
  source = "./modules/eks-nodegroup"

  eks_cluster_name    = module.eks_cluster.eks_cluster_name
  public_subnets_ids  = module.aws_vpc.public_subnets_ids
  private_subnets_ids = module.aws_vpc.private_subnets_ids
  resource_name_prefix = "taskmanager-"

  node_groups = [
    {
      name           = "nodegroup-ondemand-app"
      ami_type       = "AL2_x86_64"
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 20
      scaling_config = {
        desired_size = var.node_desired_size
        max_size     = var.node_max_size
        min_size     = var.node_min_size
      }
    }
  ]

  addons = [
    { name = "kube-proxy",        version = "v1.28.2-eksbuild.2"  },
    { name = "vpc-cni",           version = "v1.15.0-eksbuild.2"  },
    { name = "coredns",           version = "v1.10.1-eksbuild.4"  },
    { name = "aws-ebs-csi-driver", version = "v1.23.0-eksbuild.1" }
  ]

  depends_on = [module.eks_cluster]
}

# ---- Module RDS PostgreSQL ----
module "rds_taskdb" {
  source     = "./modules/rds"
  aws_region = var.aws_region

  database_configurations = [
    {
      identifier              = "taskmanager-db"
      engine                  = "postgres"
      engine_version          = "15.4"
      allocated_storage       = 20
      instance_class          = var.rds_instance_class
      db_name                 = "taskdb"
      db_username             = "taskadmin"
      db_password             = var.db_password
      parameter_group_name    = "default.postgres15"
      db_subnet_group_name    = module.aws_vpc.rds_subnet_group_name
      skip_final_snapshot     = var.environment != "prod"
      publicly_accessible     = false
      backup_retention_period = var.environment == "prod" ? 7 : 0
      multi_az                = var.environment == "prod"
      vpc_id                  = module.aws_vpc.vpc_id
      allowed_cidrs           = [module.aws_vpc.vpc_cidr]
      sg_name                 = "taskmanager-db-sg"
      sg_description          = "Security Group pour la base de données TaskManager"
      port                    = 5432
    }
  ]

  # Replica uniquement en prod
  create_replica = var.environment == "prod"

  replica_configurations = var.environment == "prod" ? [
    {
      identifier              = "taskmanager-db-replica"
      instance_class          = var.rds_instance_class
      skip_final_snapshot     = false
      backup_retention_period = 7
      replicate_source_db     = "taskmanager-db"
      multi_az                = false
      apply_immediately       = true
    }
  ] : []
}

# ---- Namespace Kubernetes ----
resource "kubernetes_namespace" "taskmanager" {
  metadata {
    name = "taskmanager"
    labels = {
      app         = "taskmanager"
      environment = var.environment
    }
  }

  depends_on = [module.eks_nodegroup]
}

# ---- Secret Kubernetes — credentials DB (injecté depuis Terraform) ----
resource "kubernetes_secret" "taskmanager_db" {
  metadata {
    name      = "taskmanager-db-secret"
    namespace = kubernetes_namespace.taskmanager.metadata[0].name
  }

  data = {
    DB_URL      = "jdbc:postgresql://${module.rds_taskdb.master_db_endpoint}/taskdb"
    DB_USERNAME = "taskadmin"
    DB_PASSWORD = var.db_password
  }

  type = "Opaque"
}

# ---- Helm Release — déploiement de l'application ----
resource "helm_release" "taskmanager" {
  name       = "taskmanager"
  chart      = "../../helm/taskmanager"
  namespace  = kubernetes_namespace.taskmanager.metadata[0].name

  set {
    name  = "image.tag"
    value = var.app_image_tag
  }

  set {
    name  = "replicaCount"
    value = var.environment == "prod" ? 3 : 1
  }

  set {
    name  = "environment"
    value = var.environment
  }

  depends_on = [
    kubernetes_secret.taskmanager_db,
    module.eks_nodegroup
  ]
}
