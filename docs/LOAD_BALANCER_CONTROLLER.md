# AWS Load Balancer Controller Setup

This guide walks through installing the AWS Load Balancer Controller on your EKS cluster.

## Prerequisites

- EKS cluster is running
- `kubectl` is configured to connect to your cluster
- `helm` is installed on your local machine

## Installation Steps

### 1. Configure kubectl

First, ensure your kubectl is configured to connect to the EKS cluster:

```bash
aws eks update-kubeconfig --region eu-west-1 --name eks-demo-demo
```

Verify the connection:

```bash
kubectl get nodes
```

### 2. Install Helm (if not already installed)

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 3. Add the EKS Helm repository

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

### 4. Create ServiceAccount for AWS Load Balancer Controller

The IAM role for the Load Balancer Controller was created by Terraform. Now we need to create the ServiceAccount that uses it:

```bash
# Get the IAM role ARN from Terraform outputs
export LBC_ROLE_ARN=$(cd infra && terraform output -raw aws_load_balancer_controller_role_arn)

# Create the ServiceAccount
kubectl create serviceaccount aws-load-balancer-controller -n kube-system

# Annotate the ServiceAccount with the IAM role
kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn=$LBC_ROLE_ARN
```

### 5. Install AWS Load Balancer Controller

```bash
# Get cluster name
export CLUSTER_NAME=$(cd infra && terraform output -raw cluster_name)

# Install the controller using Helm
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=eu-west-1 \
  --set vpcId=$(cd infra && terraform output -raw vpc_id)
```

### 6. Verify Installation

Check that the controller is running:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

You should see output like:

```
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
aws-load-balancer-controller   2/2     2            2           1m
```

Check the logs:

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

### 7. Verify IngressClass

The controller should create an IngressClass named `alb`:

```bash
kubectl get ingressclass
```

You should see:

```
NAME   CONTROLLER            PARAMETERS   AGE
alb    ingress.k8s.aws/alb   <none>       1m
```

## Troubleshooting

### Controller pods not starting

Check the pod events:

```bash
kubectl describe pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Permission issues

Verify the ServiceAccount annotation:

```bash
kubectl get serviceaccount aws-load-balancer-controller -n kube-system -o yaml
```

Check IAM role trust policy allows OIDC provider:

```bash
aws iam get-role --role-name eks-demo-demo-aws-load-balancer-controller
```

### ALB not created when Ingress is deployed

Check controller logs:

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller --follow
```

Check Ingress events:

```bash
kubectl describe ingress -n demo hello-world
```

## Uninstalling

To remove the AWS Load Balancer Controller:

```bash
helm uninstall aws-load-balancer-controller -n kube-system
kubectl delete serviceaccount aws-load-balancer-controller -n kube-system
```

## References

- [AWS Load Balancer Controller Documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [AWS Load Balancer Controller Installation Guide](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)

