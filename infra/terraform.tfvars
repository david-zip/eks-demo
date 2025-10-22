# AWS Configuration
aws_region         = "eu-west-1"
availability_zones = ["eu-west-1a", "eu-west-1b"]

# Project Configuration
project_name = "eks-demo"
environment  = "demo"

# Network Configuration (2 AZs required for EKS)
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# EKS Configuration
cluster_version      = "1.28"
node_desired_size    = 2
node_min_size        = 1
node_max_size        = 3
node_instance_types  = ["t3.small"]

# Bastion Configuration
bastion_instance_type = "t3.micro"
bastion_key_name      = ""  # Leave empty to use AWS Systems Manager Session Manager
bastion_allowed_cidrs = ["0.0.0.0/0"]  # Change to your IP: ["YOUR_IP/32"]

# Tags
tags = {
  Project     = "eks-demo"
  Environment = "demo"
  ManagedBy   = "terraform"
  Purpose     = "demo"
}

