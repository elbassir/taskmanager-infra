# ============================================================
# Module VPC — TaskManager PFE DevOps
# Ressources : VPC, Subnets public/privé, IGW, NAT, Routes
# ============================================================

# ---- VPC ----
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-taskmanager-vpc"
    Environment = var.environment
    # Tags requis pour EKS (autodiscovery des subnets)
    "kubernetes.io/cluster/eks-cluster-taskmanager" = "shared"
  }
}

# ---- Sous-réseaux publics ----
resource "aws_subnet" "public" {
  count                   = length(var.public_subnets_cidr)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(var.azs, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-${element(var.azs, count.index)}-public-subnet"
    Environment = var.environment
    "kubernetes.io/role/elb"                                    = "1"
    "kubernetes.io/cluster/eks-cluster-taskmanager"             = "shared"
  }
}

# ---- Sous-réseaux privés ----
resource "aws_subnet" "private" {
  count                   = length(var.private_subnets_cidr)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(var.azs, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.environment}-${element(var.azs, count.index)}-private-subnet"
    Environment = var.environment
    "kubernetes.io/role/internal-elb"                           = "1"
    "kubernetes.io/cluster/eks-cluster-taskmanager"             = "shared"
  }
}

# ---- Subnet group RDS ----
resource "aws_db_subnet_group" "rds" {
  name       = "${var.environment}-taskmanager-rds-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "TaskManager RDS Subnet Group"
    Environment = var.environment
  }
}

# ---- Internet Gateway ----
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.environment}-taskmanager-igw"
    Environment = var.environment
  }
}

# ---- Elastic IPs pour NAT Gateways ----
resource "aws_eip" "nat" {
  count      = length(var.public_subnets_cidr)
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name        = "${var.environment}-taskmanager-nat-eip-${element(var.azs, count.index)}"
    Environment = var.environment
  }
}

# ---- NAT Gateways (un par AZ) ----
resource "aws_nat_gateway" "nat" {
  count         = length(var.public_subnets_cidr)
  allocation_id = element(aws_eip.nat[*].id, count.index)
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "${var.environment}-taskmanager-nat-${element(var.azs, count.index)}"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.igw]
}

# ---- Table de routage publique ----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.environment}-taskmanager-public-rt"
    Environment = var.environment
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---- Tables de routage privées (une par AZ) ----
resource "aws_route_table" "private" {
  count  = length(var.private_subnets_cidr)
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.environment}-taskmanager-private-rt-${element(var.azs, count.index)}"
    Environment = var.environment
  }
}

resource "aws_route" "private_nat" {
  count                  = length(var.private_subnets_cidr)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets_cidr)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
