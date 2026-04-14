# ============================================================
# Module EKS Cluster — TaskManager PFE DevOps
# ============================================================

# ---- IAM Role pour le Control Plane EKS ----
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.resource_name_prefix}EKSClusterRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.resource_name_prefix}EKSClusterRole" }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

# ---- Cluster EKS ----
resource "aws_eks_cluster" "main" {
  name     = var.cluster_config.name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.cluster_config.version

  vpc_config {
    subnet_ids              = flatten([var.public_subnets_ids, var.private_subnets_ids])
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Logging Control Plane
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller
  ]

  tags = { Name = "${var.resource_name_prefix}eks-cluster" }
}
