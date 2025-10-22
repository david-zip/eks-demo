# EKS Demo - Cost-Optimized Deployment

A complete demonstration of deploying a containerized application on Amazon EKS (Elastic Kubernetes Service) using Terraform, showcasing essential Kubernetes operations and AWS integrations.

## Overview

This project demonstrates:
- Infrastructure as Code with Terraform
- AWS EKS cluster setup with cost optimization
- Container registry (ECR) management
- Kubernetes workload deployment
- AWS Load Balancer Controller integration
- Common kubectl operations

## Architecture

### Infrastructure Components

- **VPC**: Single VPC (10.0.0.0/16) in eu-west-1
- **Subnets**: 
  - 1 Public subnet (10.0.1.0/24) in eu-west-1a
  - 1 Private subnet (10.0.2.0/24) in eu-west-1a
- **Internet Gateway**: For public subnet internet access
- **NAT Gateway**: Single NAT Gateway in public subnet (cost optimized)
- **EKS Cluster**: Kubernetes 1.28
- **Worker Nodes**: 2x t3.small spot instances (60-70% cost savings)
- **ECR Repository**: Private container registry for application images
- **Security Groups**: Configured for EKS cluster, nodes, and ALB
- **IAM Roles**: EKS cluster role, node group role, and Load Balancer Controller role with IRSA

### Cost Breakdown (Estimated Monthly)

| Resource | Cost |
|----------|------|
| EKS Control Plane | ~$72 |
| NAT Gateway | ~$32 |
| Worker Nodes (2x t3.small spot) | ~$8-12 |
| Application Load Balancer | ~$16 |
| Data Transfer & Misc | ~$5-10 |
| **Total** | **~$133-142/month** |

**Cost Saving Tips**:
- Destroy infrastructure when not in use: `terraform destroy` (saves ~$130/month)
- Only ECR storage remains (~$1/month)
- Rebuild for demos: ~15-20 minutes

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

## Essential Kubernetes Commands for Demo

### View Resources

```bash
# Get all resources in demo namespace
kubectl get all -n demo

# Get pods with more details
kubectl get pods -n demo -o wide

# Get pod details
kubectl describe pod -n demo <pod-name>

# View pod logs
kubectl logs -n demo <pod-name>

# Follow logs in real-time
kubectl logs -n demo <pod-name> -f

# View logs from previous container (if crashed)
kubectl logs -n demo <pod-name> --previous
```

### Scaling

```bash
# Scale deployment to 3 replicas
kubectl scale deployment hello-world -n demo --replicas=3

# Verify scaling
kubectl get pods -n demo -w

# Scale back to 2
kubectl scale deployment hello-world -n demo --replicas=2
```

### Rolling Updates

```bash
# Update image to new version
kubectl set image deployment/hello-world \
  -n demo \
  hello-world=<ECR_URL>/eks-demo-hello-world:v2

# Watch rollout status
kubectl rollout status deployment/hello-world -n demo

# View rollout history
kubectl rollout history deployment/hello-world -n demo

# Rollback to previous version
kubectl rollout undo deployment/hello-world -n demo
```

### Debugging

```bash
# Execute commands in a pod
kubectl exec -it -n demo <pod-name> -- /bin/sh

# Port forward for local testing
kubectl port-forward -n demo <pod-name> 8080:3000

# View events
kubectl get events -n demo --sort-by='.lastTimestamp'

# Get pod YAML
kubectl get pod -n demo <pod-name> -o yaml

# Edit deployment on the fly
kubectl edit deployment hello-world -n demo
```

### Ingress and Load Balancer

```bash
# View ingress details
kubectl describe ingress -n demo hello-world

# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller --follow

# View service endpoints
kubectl get endpoints -n demo hello-world
```

### Node Management

```bash
# Get nodes
kubectl get nodes

# Node details
kubectl describe node <node-name>

# View node resource usage
kubectl top nodes

# View pod resource usage
kubectl top pods -n demo

# Drain node (for maintenance)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Uncordon node
kubectl uncordon <node-name>
```

### Cleanup Demo Resources

```bash
# Delete application
kubectl delete -f app/k8s/

# Or delete by namespace
kubectl delete namespace demo

# Delete Load Balancer Controller
helm uninstall aws-load-balancer-controller -n kube-system
```

## Advanced Commands

### ConfigMaps and Secrets

```bash
# Create ConfigMap from literal
kubectl create configmap app-config -n demo \
  --from-literal=LOG_LEVEL=debug

# Create Secret
kubectl create secret generic app-secret -n demo \
  --from-literal=api-key=your-secret-key

# View ConfigMap
kubectl get configmap app-config -n demo -o yaml

# View Secret (base64 encoded)
kubectl get secret app-secret -n demo -o yaml
```

### Jobs and CronJobs

```bash
# Create a one-time job
kubectl create job test-job -n demo --image=busybox -- echo "Hello from Job"

# View job status
kubectl get jobs -n demo

# View job logs
kubectl logs job/test-job -n demo
```

### Resource Monitoring

```bash
# Install metrics-server (if not already installed)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# View resource usage
kubectl top nodes
kubectl top pods -n demo
```

## Project Structure

```
eks-demo/
├── README.md
├── infra/
│   ├── main.tf                    # Root module
│   ├── providers.tf               # Provider configuration
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Output values
│   ├── terraform.tfvars           # Variable values
│   └── modules/
│       ├── network/               # Network module
│       │   ├── main.tf           # VPC, subnets, gateways, security groups
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── eks/                   # EKS module
│           ├── main.tf           # EKS cluster, node group, IAM roles
│           ├── variables.tf
│           └── outputs.tf
├── app/
│   ├── app.js                     # Node.js application
│   ├── package.json               # Node.js dependencies
│   ├── Dockerfile                 # Container image definition
│   ├── .dockerignore
│   ├── build-and-push.sh         # Helper script for ECR
│   └── k8s/
│       ├── namespace.yaml         # Kubernetes namespace
│       ├── deployment.yaml        # Application deployment
│       ├── service.yaml           # Service definition
│       └── ingress.yaml           # ALB Ingress configuration
└── docs/
    └── LOAD_BALANCER_CONTROLLER.md  # LB Controller setup guide
```

## Troubleshooting

### Nodes not joining cluster

```bash
# Check node group status
aws eks describe-nodegroup \
  --cluster-name eks-demo-demo \
  --nodegroup-name eks-demo-demo-node-group

# Check EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=eks-demo-demo" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]'
```

### Pods not starting

```bash
# Check pod events
kubectl describe pod -n demo <pod-name>

# Check if image pull is failing
kubectl get events -n demo | grep -i pull

# Verify ECR access
aws ecr describe-repositories --repository-names eks-demo-hello-world
```

### ALB not created

```bash
# Check controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Check ingress events
kubectl describe ingress -n demo hello-world

# Verify IngressClass
kubectl get ingressclass
```

### Connection to EKS fails

```bash
# Update kubeconfig
aws eks update-kubeconfig --region eu-west-1 --name eks-demo-demo

# Test AWS credentials
aws sts get-caller-identity

# Verify cluster is active
aws eks describe-cluster --name eks-demo-demo --query 'cluster.status'
```

## Cleanup

To avoid ongoing costs, destroy all resources when done:

```bash
# Delete Kubernetes resources first
kubectl delete -f app/k8s/

# Delete Load Balancer Controller
helm uninstall aws-load-balancer-controller -n kube-system

# Wait for ALB to be fully deleted (check AWS Console)
# This is important - Terraform can't delete VPC if ALB exists

# Destroy Terraform infrastructure
cd infra
terraform destroy

# Confirm with 'yes' when prompted
```

**Note**: Always delete Kubernetes resources (especially Ingress) before running `terraform destroy` to ensure the ALB is properly cleaned up.

## Cost Optimization Tips

1. **Destroy when not in use**: Run `terraform destroy` after demos
2. **Use Spot Instances**: Already configured (60-70% savings)
3. **2 AZs (minimum for EKS)**: Required by AWS, but single NAT Gateway minimizes costs
4. **Right-size nodes**: t3.small is adequate for demos
5. **Minimal node count**: 2 nodes provide HA for demo
6. **ECR lifecycle policy**: Automatically removes old images

## Security Considerations

This is a **demo environment**. For production:

1. Use private subnets only for worker nodes
2. Implement VPC endpoints for AWS services
3. Enable EKS control plane logging
4. Use private ECR endpoints
5. Implement Pod Security Standards
6. Enable network policies
7. Use AWS Secrets Manager for sensitive data
8. Implement IAM roles for service accounts (IRSA) for all workloads
9. Enable GuardDuty and Security Hub
10. Regular security scanning of container images

## Next Steps

- Add CI/CD pipeline (GitHub Actions, GitLab CI)
- Implement monitoring (Prometheus, Grafana)
- Add logging (Fluentd, CloudWatch Logs)
- Implement auto-scaling (HPA, Cluster Autoscaler)
- Add SSL/TLS with ACM certificates
- Implement network policies
- Add Helm charts for application deployment

## References

- [EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

## License

MIT License - feel free to use this for learning and demos.
