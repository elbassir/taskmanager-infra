# ============================================================
# Outputs — Infrastructure TaskManager PFE DevOps
# ============================================================

# ---- VPC ----
output "vpc_id" {
  description = "ID du VPC créé"
  value       = module.aws_vpc.vpc_id
}

output "vpc_cidr" {
  description = "Bloc CIDR du VPC"
  value       = module.aws_vpc.vpc_cidr
}

output "public_subnets_ids" {
  description = "IDs des sous-réseaux publics"
  value       = module.aws_vpc.public_subnets_ids
}

output "private_subnets_ids" {
  description = "IDs des sous-réseaux privés"
  value       = module.aws_vpc.private_subnets_ids
}

output "nat_gateways_ids" {
  description = "IDs des NAT Gateways"
  value       = module.aws_vpc.nat_gateways_ids
}

output "elastic_ips" {
  description = "IPs Elastic associées aux NAT Gateways"
  value       = module.aws_vpc.elastic_ips
}

# ---- EKS ----
output "eks_cluster_name" {
  description = "Nom du cluster EKS"
  value       = module.eks_cluster.eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint du cluster EKS"
  value       = module.eks_cluster.eks_cluster_endpoint
  sensitive   = true
}

output "eks_cluster_arn" {
  description = "ARN du cluster EKS"
  value       = module.eks_cluster.eks_cluster_arn
}

output "node_group_arns" {
  description = "ARNs des node groups EKS"
  value       = module.eks_nodegroup.node_group_arns
}

output "configure_kubectl" {
  description = "Commande pour configurer kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks_cluster.eks_cluster_name}"
}

# ---- RDS PostgreSQL ----
output "rds_master_endpoint" {
  description = "Endpoint de la base de données principale"
  value       = module.rds_taskdb.master_db_endpoint
  sensitive   = true
}

output "rds_master_identifier" {
  description = "Identifiant de l'instance RDS principale"
  value       = module.rds_taskdb.master_db_identifier
}

output "rds_replica_endpoint" {
  description = "Endpoint du réplica RDS (prod uniquement)"
  value       = module.rds_taskdb.replica_db_endpoint
  sensitive   = true
}

# ---- Application ----
output "kubernetes_namespace" {
  description = "Namespace Kubernetes de l'application"
  value       = kubernetes_namespace.taskmanager.metadata[0].name
}
