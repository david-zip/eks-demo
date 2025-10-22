# Network Module
module "network" {
  source = "./modules/network"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
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

# Bastion/Management Host Module
module "bastion" {
  source = "./modules/bastion"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.network.vpc_id
  public_subnet_id    = module.network.public_subnet_ids[0]
  cluster_name        = module.eks.cluster_name
  aws_region          = var.aws_region
  instance_type       = var.bastion_instance_type
  key_name            = var.bastion_key_name
  allowed_cidr_blocks = var.bastion_allowed_cidrs
  tags                = var.tags

  depends_on = [module.eks]
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

