# ============================================================
# Module EKS Node Group — TaskManager PFE DevOps
# ============================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_eks_cluster" "main" { name = var.eks_cluster_name }

locals {
  oidc = trimprefix(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://")
}

# ---- IAM Role pour les nœuds EC2 ----
resource "aws_iam_role" "node_group_role" {
  name = "${var.resource_name_prefix}EKSNodeGroupRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.node_group_role.name
}

# ---- Node Groups ----
resource "aws_eks_node_group" "nodes" {
  for_each = { for ng in var.node_groups : ng.name => ng }

  cluster_name    = var.eks_cluster_name
  node_group_name = each.value.name
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = var.private_subnets_ids   # Nœuds en subnet privé

  scaling_config {
    desired_size = try(each.value.scaling_config.desired_size, var.default_scaling_config.desired_size)
    max_size     = try(each.value.scaling_config.max_size, var.default_scaling_config.max_size)
    min_size     = try(each.value.scaling_config.min_size, var.default_scaling_config.min_size)
  }

  update_config {
    max_unavailable = 1
  }

  ami_type       = each.value.ami_type
  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  disk_size      = each.value.disk_size

  depends_on = [
    aws_iam_role_policy_attachment.worker_node_policy,
    aws_iam_role_policy_attachment.ecr_readonly,
    aws_iam_role_policy_attachment.cni_policy
  ]

  tags = { Name = "${var.resource_name_prefix}${each.value.name}" }
}

# ---- Add-ons EKS ----
resource "aws_eks_addon" "addons" {
  for_each = { for addon in var.addons : addon.name => addon }

  cluster_name                = var.eks_cluster_name
  addon_name                  = each.value.name
  addon_version               = each.value.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  service_account_role_arn = each.key == "aws-ebs-csi-driver" ? aws_iam_role.ebs_csi_role.arn : null

  depends_on = [aws_eks_node_group.nodes, aws_iam_role_policy_attachment.ebs_csi_role_policy]
  tags       = { Name = "${var.resource_name_prefix}addon-${each.value.name}" }
}

# ---- OIDC Provider (requis pour IRSA) ----
resource "aws_iam_openid_connect_provider" "oidc" {
  url             = "https://${local.oidc}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
  tags            = { Name = "${var.resource_name_prefix}oidc-provider" }
}

# ---- IAM Role IRSA pour EBS CSI Driver ----
resource "aws_iam_role" "ebs_csi_role" {
  name = "${var.resource_name_prefix}EBSCSIDriverRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.oidc.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${local.oidc}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.resource_name_prefix}EBSCSIDriverRole" }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_role.name
}
