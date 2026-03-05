# =====================================================
# Variable Values
# =====================================================

region       = "us-east-1"
name         = "tetris"
environment  = "dev"
cluster_name = "tetris-cluster"
cidr_block   = "10.0.0.0/16"

# Lock this down to your IP/VPN CIDR in production:
# public_access_cidrs = ["203.0.113.0/32"]
public_access_cidrs = ["0.0.0.0/0"]
