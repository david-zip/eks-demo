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
        Sid    = "EKSClusterAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:ListUpdates",
          "eks:DescribeUpdate",
          "eks:AccessKubernetesApi",
          "eks:ListFargateProfiles",
          "eks:DescribeFargateProfile",
          "eks:ListAddons",
          "eks:DescribeAddon"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for ECR Access (pull and push images)
resource "aws_iam_policy" "bastion_ecr_access" {
  name = "${var.project_name}-${var.environment}-bastion-ecr-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuthentication"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRRepositoryAccess"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:GetRepositoryPolicy"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for EC2 Read-Only Access (troubleshooting)
resource "aws_iam_policy" "bastion_ec2_readonly" {
  name = "${var.project_name}-${var.environment}-bastion-ec2-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2ReadOnlyAccess"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:Get*",
          "elasticloadbalancing:Describe*",
          "autoscaling:Describe*",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:Describe*",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# Attach policies to bastion role
resource "aws_iam_role_policy_attachment" "bastion_eks_access" {
  policy_arn = aws_iam_policy.bastion_eks_access.arn
  role       = aws_iam_role.bastion.name
}

resource "aws_iam_role_policy_attachment" "bastion_ecr_access" {
  policy_arn = aws_iam_policy.bastion_ecr_access.arn
  role       = aws_iam_role.bastion.name
}

resource "aws_iam_role_policy_attachment" "bastion_ec2_readonly" {
  policy_arn = aws_iam_policy.bastion_ec2_readonly.arn
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

# Note: Bastion security group is now created in the network module
# to avoid circular dependencies with EKS cluster security group rules

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
    echo "Installing kubectl..."
    cd /tmp
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    
    # Verify kubectl installation
    kubectl version --client
    echo "kubectl installed successfully: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    
    # Install helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ec2-user
    
    # Configure kubectl for EKS
    echo "Configuring kubectl for EKS cluster: ${var.cluster_name}..."
    REGION=$(ec2-metadata --availability-zone | sed 's/[a-z]$//' | cut -d' ' -f2)
    aws eks update-kubeconfig --region $REGION --name ${var.cluster_name}
    
    # Test kubectl connection
    echo "Testing kubectl connection..."
    kubectl get nodes || echo "kubectl configured but cluster not yet accessible (this is normal during initial setup)"
    
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
    echo "Configuring kubectl for ec2-user..."
    REGION=$(ec2-metadata --availability-zone | sed 's/[a-z]$//' | cut -d' ' -f2)
    sudo -u ec2-user aws eks update-kubeconfig --region $REGION --name ${var.cluster_name} || true
    
    # Create a verification script
    cat > /home/ec2-user/verify-tools.sh << 'VERIFY'
    #!/bin/bash
    echo "=========================================="
    echo "Tool Verification"
    echo "=========================================="
    echo "kubectl version: $(kubectl version --client --short 2>/dev/null || kubectl version --client | head -1)"
    echo "helm version: $(helm version --short)"
    echo "aws-cli version: $(aws --version)"
    echo "docker version: $(docker --version)"
    echo "git version: $(git --version)"
    echo "=========================================="
    echo "kubectl config: $(kubectl config view --minify -o jsonpath='{.clusters[0].name}' 2>/dev/null || echo 'Not configured')"
    echo "=========================================="
    VERIFY
    
    chmod +x /home/ec2-user/verify-tools.sh
    chown ec2-user:ec2-user /home/ec2-user/verify-tools.sh
    
    # Log completion
    echo "Bastion host setup complete at $(date)" | tee /var/log/user-data-complete.log
    
    # Run verification
    sudo -u ec2-user /home/ec2-user/verify-tools.sh | tee -a /var/log/user-data-complete.log
  EOF
}

# EC2 Instance
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.bastion_sg_id]
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

