# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM Role for Bastion Host
resource "aws_iam_role" "bastion" {
  name = "${var.project_name}-${var.environment}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# IAM Policy for EKS Access
resource "aws_iam_policy" "bastion_eks_access" {
  name = "${var.project_name}-${var.environment}-bastion-eks-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:ListUpdates",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# Attach EKS access policy
resource "aws_iam_role_policy_attachment" "bastion_eks_access" {
  policy_arn = aws_iam_policy.bastion_eks_access.arn
  role       = aws_iam_role.bastion.name
}

# Attach SSM policy for Session Manager access (no SSH key needed)
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.bastion.name
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-${var.environment}-bastion-profile"
  role = aws_iam_role.bastion.name

  tags = var.tags
}

# Security Group for Bastion
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-${var.environment}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  # SSH access
  ingress {
    description = "SSH from allowed IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Outbound internet access
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-bastion-sg"
    }
  )
}

# User Data Script to bootstrap the instance
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e
    
    # Update system
    dnf update -y
    
    # Install necessary packages
    dnf install -y git curl wget unzip docker
    
    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    
    # Install helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user
    
    # Configure kubectl for EKS
    aws eks update-kubeconfig --region $(ec2-metadata --availability-zone | sed 's/[a-z]$//' | cut -d' ' -f2) --name ${var.cluster_name}
    
    # Create a helper script for ec2-user
    cat > /home/ec2-user/setup-eks.sh << 'SCRIPT'
    #!/bin/bash
    echo "Configuring kubectl for EKS cluster: ${var.cluster_name}"
    aws eks update-kubeconfig --region $(ec2-metadata --availability-zone | sed 's/[a-z]$//' | cut -d' ' -f2) --name ${var.cluster_name}
    echo "Testing connection..."
    kubectl get nodes
    SCRIPT
    
    chmod +x /home/ec2-user/setup-eks.sh
    chown ec2-user:ec2-user /home/ec2-user/setup-eks.sh
    
    # Create welcome message
    cat > /etc/motd << 'MOTD'
    ╔════════════════════════════════════════════════════════╗
    ║          EKS Demo - Bastion/Management Host            ║
    ╚════════════════════════════════════════════════════════╝
    
    Tools installed:
      • kubectl (Kubernetes CLI)
      • helm (Kubernetes package manager)
      • aws-cli (AWS command line)
      • docker (Container runtime)
      • git
    
    Quick commands:
      kubectl get nodes              # View cluster nodes
      kubectl get pods -A            # View all pods
      kubectl cluster-info           # Cluster information
      ./setup-eks.sh                 # Reconfigure kubectl
    
    Cluster: ${var.cluster_name}
    
    ╚════════════════════════════════════════════════════════╝
    MOTD
    
    # Run setup for ec2-user
    sudo -u ec2-user aws eks update-kubeconfig --region $(ec2-metadata --availability-zone | sed 's/[a-z]$//' | cut -d' ' -f2) --name ${var.cluster_name} || true
    
    echo "Bastion host setup complete!" > /var/log/user-data-complete.log
  EOF
}

# EC2 Instance
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  key_name               = var.key_name != "" ? var.key_name : null
  
  user_data = local.user_data

  root_block_device {
    volume_size           = 35
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-bastion"
    }
  )
}

# Elastic IP for consistent access
resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-bastion-eip"
    }
  )
}

