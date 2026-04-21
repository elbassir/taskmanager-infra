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

  public_subnets_ids   = module.aws_vpc.public_subnets_ids
  private_subnets_ids  = module.aws_vpc.private_subnets_ids
  resource_name_prefix = "taskmanager-"
}

# ---- Module EKS Node Group ----
module "eks_nodegroup" {
  source = "./modules/eks-nodegroup"

  eks_cluster_name     = module.eks_cluster.eks_cluster_name
  public_subnets_ids   = module.aws_vpc.public_subnets_ids
  private_subnets_ids  = module.aws_vpc.private_subnets_ids
  resource_name_prefix = "taskmanager-"

  node_groups = [
    {
      name           = "nodegroup-ondemand-app"
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.small"]
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
    { name = "kube-proxy", version = "v1.30.9-eksbuild.3" },
    { name = "vpc-cni", version = "v1.20.4-eksbuild.2" },
    { name = "coredns", version = "v1.11.1-eksbuild.4" },
    { name = "aws-ebs-csi-driver", version = "v1.56.0-eksbuild.1" }
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
      engine_version          = "16.6"
      allocated_storage       = 20
      instance_class          = var.rds_instance_class
      db_name                 = "taskdb"
      db_username             = "taskadmin"
      db_password             = var.db_password
      parameter_group_name    = "default.postgres16"
      db_subnet_group_name    = module.aws_vpc.rds_subnet_group_name
      skip_final_snapshot     = var.environment != "prod"
      publicly_accessible     = false
      backup_retention_period = var.environment == "prod" ? 7 : 0
      multi_az                = var.environment == "prod"
      vpc_id                  = module.aws_vpc.vpc_id
      allowed_cidrs           = [module.aws_vpc.vpc_cidr]
      sg_name                 = "taskmanager-db-sg"
      sg_description          = "Security Group for TaskManager database"
      port                    = 5432
    }
  ]

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

# ============================================================
# AWS LOAD BALANCER CONTROLLER
# Requis pour que l'Ingress crée automatiquement un ALB AWS
# ============================================================

# ---- Policy IAM pour le Load Balancer Controller ----
resource "aws_iam_policy" "alb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "Policy pour AWS Load Balancer Controller sur EKS"
  policy      = file("${path.module}/alb-controller-policy.json")
}

# ---- IAM Role (IRSA) pour le Service Account du Controller ----
resource "aws_iam_role" "alb_controller" {
  name = "AmazonEKSLoadBalancerControllerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks_nodegroup.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(module.eks_nodegroup.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(module.eks_nodegroup.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  depends_on = [module.eks_nodegroup]
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# ---- Service Account Kubernetes pour le Controller ----
resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }
  }
  depends_on = [
    module.eks_nodegroup,
    aws_iam_role_policy_attachment.alb_controller
  ]
}

# ---- Helm Release — AWS Load Balancer Controller ----
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.2"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks_cluster.eks_cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = module.aws_vpc.vpc_id
  }

  depends_on = [
    kubernetes_service_account.alb_controller,
    aws_iam_role_policy_attachment.alb_controller,
    module.eks_nodegroup
  ]
}

# ============================================================
# KUBERNETES — Namespace, Secrets, Application
# ============================================================

# ---- Namespace Kubernetes ----
resource "kubernetes_namespace" "taskmanager" {
  metadata {
    name = "taskmanager"
  }
  depends_on = [module.eks_nodegroup]
}

# ---- Secret Kubernetes — credentials DB ----
resource "kubernetes_secret" "taskmanager_db" {
  metadata {
    name      = "taskmanager-db-secret"
    namespace = kubernetes_namespace.taskmanager.metadata[0].name
  }
  data = {
    DB_URL      = "jdbc:postgresql://${module.rds_taskdb.master_db_endpoint["0"]}/taskdb"
    DB_USERNAME = "taskadmin"
    DB_PASSWORD = var.db_password
  }
  type = "Opaque"
}

# ---- Secret Kubernetes — auth GHCR (pull image Docker) ----
resource "kubernetes_secret" "ghcr_secret" {
  metadata {
    name      = "ghcr-secret"
    namespace = kubernetes_namespace.taskmanager.metadata[0].name
  }
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.ghcr_username
          password = var.ghcr_token
          auth     = base64encode("${var.ghcr_username}:${var.ghcr_token}")
        }
      }
    })
  }
  type = "kubernetes.io/dockerconfigjson"
}

# ---- Helm Release — Application TaskManager ----
resource "helm_release" "taskmanager" {
  name      = "taskmanager"
  chart     = "../../helm/taskmanager"
  namespace = kubernetes_namespace.taskmanager.metadata[0].name

  timeout = 600
  wait    = true

  set {
    name  = "image.repository"
    value = "ghcr.io/${var.ghcr_username}/taskmanager"
  }
  set {
    name  = "image.tag"
    value = var.app_image_tag
  }
  set {
    name  = "imagePullSecrets[0].name"
    value = "ghcr-secret"
  }

  depends_on = [
    helm_release.alb_controller, # ALB Controller doit être prêt avant l'app
    kubernetes_secret.taskmanager_db,
    kubernetes_secret.ghcr_secret,
    module.eks_nodegroup
  ]
}
