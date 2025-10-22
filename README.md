# EKS Demo

A complete demonstration of deploying a containerized application on Amazon EKS (Elastic Kubernetes Service) using Terraform, showcasing essential Kubernetes operations and AWS integrations.

## Architecture

### Infrastructure Components

- **VPC**: Single VPC in eu-west-1
- **Subnets**: 
  - 1 Public subnet in eu-west-1a
  - 1 Private subnet in eu-west-1a
- **Internet Gateway**: For public subnet internet access
- **NAT Gateway**: Single NAT Gateway in public subnet
- **EKS Cluster**: Kubernetes 1.28
- **Worker Nodes**: 2x t3.small spot instances
- **ECR Repository**: Private container registry for application images
- **Security Groups**: Configured for EKS cluster, nodes, and ALB
- **IAM Roles**: EKS cluster role, node group role, and Load Balancer Controller role with IRSA

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- Docker
- kubectl
- Helm 3
- Git

### Install Prerequisites (macOS)

```bash
# Homebrew
brew install awscli terraform kubectl helm docker

# Configure AWS CLI
aws configure
```

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd eks-demo
```

### 2. Deploy Infrastructure

```bash
cd infra

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply

# This will take approximately 15-20 minutes
```

### 3. Configure kubectl

```bash
# Get the configure command from Terraform output
terraform output configure_kubectl

# Or run directly
aws eks update-kubeconfig --region eu-west-1 --name eks-demo-demo

# Verify connection
kubectl get nodes
```

You should see 2 worker nodes in Ready state.

### 4. Install AWS Load Balancer Controller

Follow the detailed instructions in [docs/LOAD_BALANCER_CONTROLLER.md](docs/LOAD_BALANCER_CONTROLLER.md)

Quick commands:

```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get IAM role ARN
export LBC_ROLE_ARN=$(cd infra && terraform output -raw aws_load_balancer_controller_role_arn)

# Create ServiceAccount
kubectl create serviceaccount aws-load-balancer-controller -n kube-system
kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn=$LBC_ROLE_ARN

# Install controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=eks-demo-demo \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=eu-west-1 \
  --set vpcId=$(cd infra && terraform output -raw vpc_id)

# Verify
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### 5. Build and Push Application to ECR

```bash
cd app

# Build and push using the provided script
./build-and-push.sh

# Or manually:
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=eu-west-1
export ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URL

# Build and tag
docker build -t eks-demo-hello-world:latest .
docker tag eks-demo-hello-world:latest \
  ${ECR_URL}/eks-demo-hello-world:latest

# Push
docker push ${ECR_URL}/eks-demo-hello-world:latest
```

### 6. Update Kubernetes Manifests

Update the image URL in `app/k8s/deployment.yaml`:

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# macOS
sed -i '' "s/<AWS_ACCOUNT_ID>/${AWS_ACCOUNT_ID}/g" k8s/deployment.yaml

# Linux
sed -i "s/<AWS_ACCOUNT_ID>/${AWS_ACCOUNT_ID}/g" k8s/deployment.yaml
```

### 7. Deploy Application to Kubernetes

```bash
cd app/k8s

# Deploy all resources
kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml

# Or deploy everything at once
kubectl apply -f .
```

### 8. Verify Deployment

```bash
# Check namespace
kubectl get namespaces

# Check all resources in demo namespace
kubectl get all -n demo

# Check pods are running
kubectl get pods -n demo

# Check service
kubectl get svc -n demo

# Check ingress
kubectl get ingress -n demo

# Get ALB URL (wait a few minutes for ALB to provision)
kubectl get ingress -n demo hello-world -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### 9. Test Application

```bash
# Get the ALB URL
export ALB_URL=$(kubectl get ingress -n demo hello-world -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test the application
curl http://$ALB_URL

# Or open in browser
echo "Application URL: http://$ALB_URL"
```

Expected response:
```json
{
  "message": "Hello from EKS Demo!",
  "hostname": "hello-world-xxxxxxxxxx-xxxxx",
  "timestamp": "2024-01-01T12:00:00.000Z",
  "version": "1.0.0"
}
```

## References

- [EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
