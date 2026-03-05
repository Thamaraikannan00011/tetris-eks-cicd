variable "cluster_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "eks_cluster_role_arn" {
  type = string
}

variable "eks_nodes_role_arn" {
  type = string
}

variable "eks_cluster_sg_id" {
  type = string
}

variable "public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
