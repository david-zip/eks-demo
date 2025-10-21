#!/bin/bash

# Complete cleanup script for EKS Demo
# This script ensures all resources are properly deleted to avoid costs

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}EKS Demo - Complete Cleanup${NC}"
echo "======================================"
echo ""
echo -e "${YELLOW}This will delete all demo resources.${NC}"
echo -e "${YELLOW}Press Ctrl+C to cancel, or Enter to continue...${NC}"
read

# Step 1: Delete Kubernetes resources
echo -e "${GREEN}Step 1: Deleting Kubernetes resources...${NC}"
if kubectl get namespace demo &> /dev/null; then
    echo "Deleting demo namespace and all resources..."
    kubectl delete namespace demo --timeout=5m || true
else
    echo "Demo namespace not found, skipping..."
fi
echo ""

# Step 2: Delete AWS Load Balancer Controller
echo -e "${GREEN}Step 2: Deleting AWS Load Balancer Controller...${NC}"
if helm list -n kube-system | grep -q aws-load-balancer-controller; then
    echo "Uninstalling Load Balancer Controller..."
    helm uninstall aws-load-balancer-controller -n kube-system || true
    kubectl delete serviceaccount aws-load-balancer-controller -n kube-system || true
else
    echo "Load Balancer Controller not found, skipping..."
fi
echo ""

# Step 3: Wait for ALB deletion
echo -e "${GREEN}Step 3: Waiting for ALB to be deleted...${NC}"
echo "Checking for Application Load Balancers..."
ALB_COUNT=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-demo`)].LoadBalancerArn' --output text 2>/dev/null | wc -l)

if [ "$ALB_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}Found ALBs created by Kubernetes. Waiting for deletion...${NC}"
    echo "This may take 2-3 minutes..."
    
    for i in {1..60}; do
        ALB_COUNT=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-demo`)].LoadBalancerArn' --output text 2>/dev/null | wc -l)
        if [ "$ALB_COUNT" -eq 0 ]; then
            echo -e "${GREEN}All ALBs deleted successfully!${NC}"
            break
        fi
        echo -n "."
        sleep 3
    done
    echo ""
else
    echo "No ALBs found, continuing..."
fi
echo ""

# Step 4: Destroy Terraform infrastructure
echo -e "${GREEN}Step 4: Destroying Terraform infrastructure...${NC}"
cd infra

echo "Running terraform destroy..."
terraform destroy -auto-approve

echo ""
echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo ""
echo -e "${YELLOW}Remaining resources (minimal cost):${NC}"
echo "  - ECR Repository (with images): ~$1/month"
echo "  - S3 Terraform state (if using remote backend): ~$0.02/month"
echo ""
echo "To remove ECR repository:"
echo "  aws ecr delete-repository --repository-name eks-demo-hello-world --force --region eu-west-1"
echo ""
echo -e "${GREEN}All major cost resources have been removed!${NC}"

