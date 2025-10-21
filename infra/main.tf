# Network Module
module "network" {
  source = "./modules/network"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zone    = var.availability_zone
  public_subnet_cidr   = var.public_subnet_cidr
  private_subnet_cidr  = var.private_subnet_cidr
  tags                 = var.tags
}

# EKS Module
module "eks" {
  source = "./modules/eks"

  cluster_name              = "${var.project_name}-${var.environment}"
  cluster_version           = var.cluster_version
  vpc_id                    = module.network.vpc_id
  private_subnet_ids        = module.network.private_subnet_ids
  cluster_security_group_id = module.network.eks_cluster_security_group_id
  node_security_group_id    = module.network.eks_nodes_security_group_id
  node_desired_size         = var.node_desired_size
  node_min_size             = var.node_min_size
  node_max_size             = var.node_max_size
  node_instance_types       = var.node_instance_types
  tags                      = var.tags

  depends_on = [module.network]
}

# ECR Repository for Hello World App
resource "aws_ecr_repository" "hello_world" {
  name                 = "${var.project_name}-hello-world"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "hello_world" {
  repository = aws_ecr_repository.hello_world.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

