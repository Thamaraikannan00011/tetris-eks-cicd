# =====================================================
# VPC Module - 3-AZ High Availability
# =====================================================
# Layout:
#   us-east-1a : public 10.0.1.0/24  | private 10.0.10.0/24
#   us-east-1b : public 10.0.2.0/24  | private 10.0.20.0/24
#   us-east-1c : public 10.0.3.0/24  | private 10.0.30.0/24
#
# Public subnets  → ALB
# Private subnets → EKS nodes (internet via NAT GW)
#
# One NAT Gateway per AZ for true HA (no cross-AZ single point of failure)
# =====================================================

locals {
  azs = ["${var.region}a", "${var.region}b", "${var.region}c"]

  public_cidrs  = ["10.0.1.0/24",  "10.0.2.0/24",  "10.0.3.0/24"]
  private_cidrs = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
}

# ===== VPC =====
resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

# ===== INTERNET GATEWAY =====
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name}-igw" }
}

# ===== PUBLIC SUBNETS (3 AZs) =====
resource "aws_subnet" "public" {
  count = 3

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name                                        = "${var.name}-public-${count.index + 1}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ===== PRIVATE SUBNETS (3 AZs) =====
resource "aws_subnet" "private" {
  count = 3

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name                                        = "${var.name}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ===== NAT GATEWAYS - one per AZ for true HA =====
resource "aws_eip" "nat" {
  count  = 3
  domain = "vpc"

  tags = { Name = "${var.name}-nat-eip-${count.index + 1}" }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  count = 3

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = { Name = "${var.name}-nat-${count.index + 1}" }

  depends_on = [aws_internet_gateway.igw]
}

# ===== PUBLIC ROUTE TABLE (shared across all public subnets) =====
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ===== PRIVATE ROUTE TABLES - one per AZ (each routes to its own NAT GW) =====
resource "aws_route_table" "private" {
  count  = 3
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }

  tags = { Name = "${var.name}-private-rt-${count.index + 1}" }
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =====================================================
# SECURITY GROUPS
# =====================================================

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "ALB: HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-alb-sg" }
}

# EKS Cluster Control Plane Security Group
# No ingress inline - added via aws_security_group_rule to avoid cycle
resource "aws_security_group" "eks_cluster" {
  name        = "${var.name}-eks-cluster-sg"
  description = "EKS control plane"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-eks-cluster-sg" }
}

# EKS Nodes Security Group
# No cross-SG ingress inline - added via aws_security_group_rule to avoid cycle
resource "aws_security_group" "eks_nodes" {
  name        = "${var.name}-eks-nodes-sg"
  description = "EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  # ALB → nodes
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "ALB to node services"
  }

  # Node-to-node TCP
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
    description = "Node-to-node TCP"
  }

  # Node-to-node UDP (CNI)
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    self        = true
    description = "Node-to-node UDP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-eks-nodes-sg" }
}

# ===== SECURITY GROUP RULES (cross-SG, added after both SGs exist) =====

# Nodes → control plane (HTTPS)
resource "aws_security_group_rule" "nodes_to_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_nodes.id
  description              = "Nodes to control plane HTTPS"
}

# Control plane → nodes (HTTPS)
resource "aws_security_group_rule" "cluster_to_nodes_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.eks_cluster.id
  description              = "Control plane to nodes HTTPS"
}

# Control plane → nodes (ephemeral ports)
resource "aws_security_group_rule" "cluster_to_nodes_ephemeral" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.eks_cluster.id
  description              = "Control plane to nodes ephemeral ports"
}
