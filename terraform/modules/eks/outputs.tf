output "cluster_name" { 
  value = aws_eks_cluster.main.name 
}
output "cluster_endpoint" { 
  value = aws_eks_cluster.main.endpoint 
}
output "cluster_version" { 
  value = aws_eks_cluster.main.version 
}
output "cluster_platform_version" { 
  value = aws_eks_cluster.main.platform_version 
}
output "cluster_security_group_id" { 
  value = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id 
}
output "cluster_certificate_authority" {
  value     = aws_eks_cluster.main.certificate_authority[0].data
  sensitive = true
}
output "oidc_provider_arn" { 
  value = aws_iam_openid_connect_provider.cluster.arn 
}
output "on_demand_node_group_status" { 
  value = aws_eks_node_group.on_demand.status 
}
output "spot_node_group_status" { 
  value = aws_eks_node_group.spot.status 
}
