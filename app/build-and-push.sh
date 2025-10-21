#!/bin/bash

# Script to build and push Docker image to ECR

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}EKS Demo - Build and Push to ECR${NC}"
echo "======================================"

# Get AWS account ID and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-eu-west-1}
REPOSITORY_NAME="eks-demo-hello-world"
IMAGE_TAG=${IMAGE_TAG:-latest}

echo -e "${YELLOW}AWS Account ID:${NC} $AWS_ACCOUNT_ID"
echo -e "${YELLOW}AWS Region:${NC} $AWS_REGION"
echo -e "${YELLOW}Repository:${NC} $REPOSITORY_NAME"
echo -e "${YELLOW}Image Tag:${NC} $IMAGE_TAG"
echo ""

# ECR repository URL
ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
FULL_IMAGE_NAME="${ECR_URL}/${REPOSITORY_NAME}:${IMAGE_TAG}"

# Login to ECR
echo -e "${GREEN}Step 1: Logging into ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
echo ""

# Build Docker image
echo -e "${GREEN}Step 2: Building Docker image...${NC}"
docker build -t $REPOSITORY_NAME:$IMAGE_TAG .
echo ""

# Tag image for ECR
echo -e "${GREEN}Step 3: Tagging image for ECR...${NC}"
docker tag $REPOSITORY_NAME:$IMAGE_TAG $FULL_IMAGE_NAME
echo ""

# Push to ECR
echo -e "${GREEN}Step 4: Pushing image to ECR...${NC}"
docker push $FULL_IMAGE_NAME
echo ""

echo -e "${GREEN}✓ Successfully pushed image to ECR!${NC}"
echo -e "${YELLOW}Image URL:${NC} $FULL_IMAGE_NAME"
echo ""
echo -e "${YELLOW}Update your Kubernetes deployment with:${NC}"
echo "  image: $FULL_IMAGE_NAME"

