locals {
  oidc_issuer = aws_eks_cluster.main.identity[0].oidc[0].issuer
  oidc_url    = replace(local.oidc_issuer, "https://", "")
}

# ===== EKS CLUSTER =====
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.eks_cluster_role_arn
  version  = "1.31"

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [var.eks_cluster_sg_id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  enabled_cluster_log_types = [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ]

  tags = { Name = var.cluster_name }
}

data "aws_caller_identity" "current" {}

# ===== ON-DEMAND NODE GROUP =====
resource "aws_eks_node_group" "on_demand" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-on-demand"
  node_role_arn   = var.eks_nodes_role_arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = 3
    min_size     = 3
    max_size     = 9
  }

  instance_types = ["t3.large"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 50

  labels = { "node-type" = "on-demand" }

  update_config {
    max_unavailable = 1
  }

  tags      = { Name = "${var.cluster_name}-on-demand-ng" }
  depends_on = [aws_eks_cluster.main]
}

# ===== SPOT NODE GROUP =====
resource "aws_eks_node_group" "spot" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-spot"
  node_role_arn   = var.eks_nodes_role_arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = 0
    min_size     = 0
    max_size     = 9
  }

  instance_types = ["t3.large", "t3a.large", "m5.large", "m5a.large", "t2.large"]
  capacity_type  = "SPOT"
  disk_size      = 50

  labels = { "node-type" = "spot" }

  taint {
    key    = "spot"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  update_config {
    max_unavailable = 1
  }

  tags      = { Name = "${var.cluster_name}-spot-ng" }
  depends_on = [aws_eks_cluster.main]
}

# ===== ADD-ON VERSIONS =====
data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

# ===== ADD-ONS =====
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.on_demand]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.on_demand]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpc_cni.version
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.vpc_cni.arn
  depends_on                  = [aws_eks_node_group.on_demand, aws_iam_role_policy_attachment.vpc_cni]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi.version
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  depends_on                  = [aws_eks_node_group.on_demand, aws_iam_role_policy_attachment.ebs_csi]
}

# ===== OIDC PROVIDER =====
resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
  url             = local.oidc_issuer

  tags = { Name = "${var.cluster_name}-oidc" }
}

# ===== IRSA: VPC CNI =====
resource "aws_iam_role" "vpc_cni" {
  name = "${var.cluster_name}-vpc-cni-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_url}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" = "system:serviceaccount:kube-system:aws-node"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni.name
}

# ===== IRSA: EBS CSI =====
resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_url}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi.name
}
