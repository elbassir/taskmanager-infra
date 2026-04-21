# ============================================================
# Variables — Infrastructure TaskManager PFE DevOps
# ============================================================

# ---- Région & Environnement ----

variable "aws_region" {
  description = "Région AWS cible (Paris par défaut)"
  type        = string
  default     = "eu-west-3"
}

locals {
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]
}

variable "environment" {
  description = "Nom de l'environnement (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "L'environnement doit être : dev, staging ou prod."
  }
}

# ---- Réseau (VPC) ----

variable "vpc_cidr" {
  description = "Bloc CIDR du VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets_cidr" {
  description = "Blocs CIDR des sous-réseaux publics (2 AZ minimum)"
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.128.0/20"]
}

variable "private_subnets_cidr" {
  description = "Blocs CIDR des sous-réseaux privés (2 AZ minimum)"
  type        = list(string)
  default     = ["10.0.16.0/20", "10.0.144.0/20"]
}

# ---- EKS ----

variable "eks_version" {
  description = "Version de Kubernetes pour le cluster EKS"
  type        = string
  default     = "1.30"
}

variable "node_desired_size" {
  description = "Nombre de nœuds souhaités dans le node group"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Nombre maximum de nœuds (auto-scaling)"
  type        = number
  default     = 4
}

variable "node_min_size" {
  description = "Nombre minimum de nœuds"
  type        = number
  default     = 1
}

# ---- RDS PostgreSQL ----

variable "rds_instance_class" {
  description = "Classe d'instance RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "db_password" {
  description = "Mot de passe du compte administrateur PostgreSQL"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 12
    error_message = "Le mot de passe doit contenir au moins 12 caractères."
  }
}

# ---- Application ----

variable "app_image_tag" {
  description = "Tag de l'image Docker de l'application à déployer"
  type        = string
  default     = "latest"
}

variable "ghcr_username" {
  description = "Nom d'utilisateur GitHub pour GHCR"
  type        = string
}

variable "ghcr_token" {
  description = "Personal Access Token GitHub (scope: read:packages)"
  type        = string
  sensitive   = true
}