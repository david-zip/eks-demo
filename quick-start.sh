#!/bin/bash

# Quick start script for EKS Demo
# This script automates the initial setup process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   EKS Demo - Quick Start Setup        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

command -v aws >/dev/null 2>&1 || { echo -e "${RED}✗ AWS CLI not found. Please install it first.${NC}"; exit 1; }
echo -e "${GREEN}✓ AWS CLI${NC}"

command -v terraform >/dev/null 2>&1 || { echo -e "${RED}✗ Terraform not found. Please install it first.${NC}"; exit 1; }
echo -e "${GREEN}✓ Terraform${NC}"

command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}✗ kubectl not found. Please install it first.${NC}"; exit 1; }
echo -e "${GREEN}✓ kubectl${NC}"

command -v helm >/dev/null 2>&1 || { echo -e "${RED}✗ Helm not found. Please install it first.${NC}"; exit 1; }
echo -e "${GREEN}✓ Helm${NC}"

command -v docker >/dev/null 2>&1 || { echo -e "${RED}✗ Docker not found. Please install it first.${NC}"; exit 1; }
echo -e "${GREEN}✓ Docker${NC}"

echo ""

# Check AWS credentials
echo -e "${BLUE}Verifying AWS credentials...${NC}"
if aws sts get-caller-identity >/dev/null 2>&1; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${GREEN}✓ AWS credentials configured${NC}"
    echo -e "${YELLOW}  Account ID: ${AWS_ACCOUNT_ID}${NC}"
else
    echo -e "${RED}✗ AWS credentials not configured. Run 'aws configure' first.${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo -e "${YELLOW}This will deploy the following:${NC}"
echo -e "${YELLOW}  • VPC with public/private subnets${NC}"
echo -e "${YELLOW}  • NAT Gateway${NC}"
echo -e "${YELLOW}  • EKS Cluster (v1.28)${NC}"
echo -e "${YELLOW}  • 2x t3.small spot instances${NC}"
echo -e "${YELLOW}  • ECR Repository${NC}"
echo -e "${YELLOW}  • Security Groups & IAM Roles${NC}"
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Estimated cost: ~$134-141/month if running 24/7${NC}"
echo -e "${YELLOW}Deployment time: ~15-20 minutes${NC}"
echo ""
echo -e "${RED}Press Ctrl+C to cancel, or Enter to continue...${NC}"
read

# Step 1: Deploy Terraform infrastructure
echo ""
echo -e "${GREEN}Step 1/5: Deploying Terraform infrastructure...${NC}"
cd infra

if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

echo "Applying Terraform configuration..."
terraform apply -auto-approve

echo -e "${GREEN}✓ Infrastructure deployed!${NC}"
echo ""

# Step 2: Configure kubectl
echo -e "${GREEN}Step 2/5: Configuring kubectl...${NC}"
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region eu-west-1 --name $CLUSTER_NAME

echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo -e "${GREEN}✓ kubectl configured!${NC}"
kubectl get nodes
echo ""

# Step 3: Install AWS Load Balancer Controller
echo -e "${GREEN}Step 3/5: Installing AWS Load Balancer Controller...${NC}"

# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update

# Get IAM role ARN
LBC_ROLE_ARN=$(terraform output -raw aws_load_balancer_controller_role_arn)
VPC_ID=$(terraform output -raw vpc_id)

# Create ServiceAccount
kubectl create serviceaccount aws-load-balancer-controller -n kube-system 2>/dev/null || true
kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn=$LBC_ROLE_ARN \
  --overwrite

# Install controller
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=eu-west-1 \
  --set vpcId=$VPC_ID \
  --wait

echo -e "${GREEN}✓ Load Balancer Controller installed!${NC}"
echo ""

# Step 4: Build and push application
echo -e "${GREEN}Step 4/5: Building and pushing application to ECR...${NC}"
cd ../app

ECR_REPO_URL=$(cd ../infra && terraform output -raw ecr_repository_url)

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin $ECR_REPO_URL

# Build image
echo "Building Docker image..."
docker build -t eks-demo-hello-world:latest .

# Tag and push
docker tag eks-demo-hello-world:latest ${ECR_REPO_URL}:latest
echo "Pushing to ECR..."
docker push ${ECR_REPO_URL}:latest

echo -e "${GREEN}✓ Application pushed to ECR!${NC}"
echo ""

# Step 5: Deploy application to Kubernetes
echo -e "${GREEN}Step 5/5: Deploying application to Kubernetes...${NC}"

# Update deployment with ECR image URL
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/deployment.yaml
rm -f k8s/deployment.yaml.bak

# Deploy
kubectl apply -f k8s/

echo "Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/hello-world -n demo

echo "Waiting for ALB to be provisioned (this may take 2-3 minutes)..."
for i in {1..60}; do
    ALB_URL=$(kubectl get ingress -n demo hello-world -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ ! -z "$ALB_URL" ]; then
        break
    fi
    echo -n "."
    sleep 3
done
echo ""

echo -e "${GREEN}✓ Application deployed!${NC}"
echo ""

# Summary
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Deployment Complete! 🎉         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Cluster Name:${NC} $CLUSTER_NAME"
echo -e "${YELLOW}Region:${NC} eu-west-1"
echo ""

# Get ALB URL
ALB_URL=$(kubectl get ingress -n demo hello-world -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending...")
if [ "$ALB_URL" != "pending..." ]; then
    echo -e "${YELLOW}Application URL:${NC} http://$ALB_URL"
    echo ""
    echo -e "${BLUE}Testing application...${NC}"
    sleep 10  # Wait a bit for ALB to be fully ready
    curl -s http://$ALB_URL || echo -e "${YELLOW}(ALB still provisioning, try again in 1-2 minutes)${NC}"
else
    echo -e "${YELLOW}Application URL:${NC} Still provisioning... (check in 2-3 minutes)"
    echo ""
    echo "Run this command to get the URL:"
    echo "  kubectl get ingress -n demo hello-world"
fi

echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo "  kubectl get all -n demo              # View all resources"
echo "  kubectl logs -n demo -l app=hello-world -f  # Follow logs"
echo "  kubectl scale deployment hello-world -n demo --replicas=3  # Scale up"
echo ""
echo -e "${BLUE}View costs and cleanup:${NC}"
echo "  cat docs/COST_OPTIMIZATION.md       # Cost optimization guide"
echo "  ./cleanup.sh                        # Destroy all resources"
echo ""
echo -e "${GREEN}Happy demoing! 🚀${NC}"

