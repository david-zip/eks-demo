# AWS Configuration
aws_region        = "eu-west-1"
availability_zone = "eu-west-1a"

# Project Configuration
project_name = "eks-demo"
environment  = "demo"

# Network Configuration
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"

# EKS Configuration
cluster_version      = "1.28"
node_desired_size    = 2
node_min_size        = 1
node_max_size        = 3
node_instance_types  = ["t3.small"]

# Tags
tags = {
  Project     = "eks-demo"
  Environment = "demo"
  ManagedBy   = "terraform"
  Purpose     = "cost-optimized-demo"
}

