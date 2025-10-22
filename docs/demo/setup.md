# EKS Demo: End-to-End Deployment Guide

This guide covers everything required to provision infrastructure with Terraform, configure access, build and push an app image to ECR, and deploy it on an EKS cluster from a bastion host.

---

## 0. Prerequisites (on Bastion)

- Verify that AWS CLI and Docker are installed:
  ```bashterrte
  aws --version
  docker --version
  ```

- Install `kubectl`:
  ```bash
  cd /tmp
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
  kubectl version --client
  ```

- Install `nano` (optional text editor):
  ```bash
  sudo yum install -y nano
  ```

- Confirm SSM session has internet access:
  ```bash
  ping -c 2 8.8.8.8
  ```

---

## 1. Provision Infrastructure with Terraform

- From your local machine or Terraform environment:
  ```bash
  terraform init
  terraform plan -out=tfplan
  terraform apply tfplan
  ```

- Resources created:
  - VPC (public/private subnets, route tables, NAT, IGW)
  - Security groups
  - EKS cluster (control plane)
  - Managed node group
  - ECR repository
  - Bastion EC2 instance (via SSM)

---

## 2. Connect to the EKS Cluster

- On bastion:
  ```bash
  aws eks list-clusters --region eu-west-1
  aws eks update-kubeconfig --region eu-west-1 --name eks-demo-demo
  ```

- Verify connection:
  ```bash
  kubectl get nodes
  ```

- If the command hangs:
  - Ensure the cluster endpoint is public **or**
  - Verify private endpoint routing (bastion in same VPC, security groups allow 443).

---

## 3. Map Bastion IAM Role to Kubernetes (aws-auth)

- Edit the aws-auth ConfigMap:
  ```bash
  kubectl edit configmap aws-auth -n kube-system
  ```

- Add under `mapRoles`:
  ```yaml
  - rolearn: arn:aws:iam::116961718874:role/eks-demo-demo-bastion-role
    username: bastion
    groups:
      - system:masters
  ```

- Verify:
  ```bash
  kubectl get nodes
  ```

---

## 4. Clone the Application Repository

- From bastion:
  ```bash
  cd /tmp
  git clone https://github.com/david-zip/eks-demo.git
  cd eks-demo
  ```

- Expected structure:
  ```
  /tmp/eks-demo/
    app/
      Dockerfile
      app.js
      package.json
      k8s/
        namespace.yaml
        deployment.yaml
        service.yaml
        ingress.yaml (optional)
    infra/
      main.tf, variables.tf, outputs.tf, etc.
  ```

---

## 5. Fix Docker Permissions (if required)

- If you see:
  ```
  permission denied while trying to connect to the Docker daemon socket
  ```
  Run:
  ```bash
  sudo usermod -aG docker ssm-user
  exit
  ```
- Reconnect SSM and test:
  ```bash
  docker ps
  ```

---

## 6. Authenticate to ECR

- Log in to ECR (as root if using `sudo docker`):
  ```bash
  sudo aws ecr get-login-password --region eu-west-1 \
  | sudo docker login --username AWS --password-stdin 116961718874.dkr.ecr.eu-west-1.amazonaws.com
  ```

- Expected output:
  ```
  Login Succeeded
  ```

---

## 7. Build, Tag, and Push the Docker Image

- Navigate to the app directory:
  ```bash
  cd /tmp/eks-demo/app
  ```

- Build and push:
  ```bash
  sudo docker build -t eks-demo-hello-world .
  sudo docker tag eks-demo-hello-world:latest 116961718874.dkr.ecr.eu-west-1.amazonaws.com/eks-demo-hello-world:latest
  sudo docker push 116961718874.dkr.ecr.eu-west-1.amazonaws.com/eks-demo-hello-world:latest
  ```

- If repository doesn’t exist:
  ```bash
  aws ecr create-repository --repository-name eks-demo-hello-world --region eu-west-1
  ```

---

## 8. Verify Image in ECR

- Confirm your image exists:
  ```bash
  aws ecr describe-images --repository-name eks-demo-hello-world --region eu-west-1
  ```

- Expected output includes:
  ```
  "imageTags": ["latest"]
  ```

---

## 9. Update Deployment YAML

- Edit deployment file:
  ```bash
  cd /tmp/eks-demo/app/k8s
  nano deployment.yaml
  ```

- Confirm the image reference:
  ```yaml
  containers:
    - name: eks-demo-app
      image: 116961718874.dkr.ecr.eu-west-1.amazonaws.com/eks-demo-hello-world:latest
      ports:
        - containerPort: 3000
          name: http
          protocol: TCP
  ```

- Save with:
  ```
  Ctrl + O, Enter, Ctrl + X
  ```

---

## 10. Apply Kubernetes Manifests

- Apply all manifests in order:
  ```bash
  kubectl apply -f namespace.yaml
  kubectl apply -f deployment.yaml
  kubectl apply -f service.yaml
  # optional
  kubectl apply -f ingress.yaml
  ```

---

## 11. Verify Deployment

- Check resources:
  ```bash
  kubectl get all -n demo
  ```

- Check logs:
  ```bash
  kubectl logs -l app=hello-world -n demo
  ```

- Expected:
  ```
  Server running on port 3000
  ```

---

## 12. Access the Application

- If Service type = LoadBalancer:
  ```bash
  kubectl get svc -n demo
  ```
  Open in browser:
  ```
  http://<EXTERNAL-IP>:3000
  ```

- If using Ingress:
  ```bash
  kubectl get ingress -n demo
  ```
  Open:
  ```
  http://<ADDRESS>
  ```

- If NodePort:
  ```bash
  kubectl get nodes -o wide
  kubectl get svc -n demo
  curl http://<node-private-ip>:<nodeport>
  ```

---

## 13. Scale and Monitor

- Scale replicas:
  ```bash
  kubectl scale deployment hello-world -n demo --replicas=4
  ```

- Watch rollout:
  ```bash
  kubectl get pods -n demo -w
  ```

- Scale range
  ```
  kubectl autoscale deployment hello-world \
    --cpu-percent=60 \
    --min=2 \
    --max=6 \
    -n demo
  ```

---

## 14. Clean Up

- Delete namespace:
  - Remove pods, deployments, ReplicaSets, and services.
  - Allow AWS to clean up associated load balancers and network interfaces.
  ```bash
  kubectl delete namespace demo
  ```

- If stuck in "Terminating":
  - Wait several minutes for AWS resources (LB, ENIs) to delete.
  - Or remove finalizers manually:
    ```bash
    kubectl get namespace demo -o json > tmp.json
    nano tmp.json
    ```
    Delete the `"finalizers"` line and run:
    ```bash
    kubectl replace --raw "/api/v1/namespaces/demo/finalize" -f ./tmp.json
    ```

- Drain nodes
  ```
  kubectl get nodes
  kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
  ```

  - mark nodes as unschedulable
    ```
    kubectl cordon <node-name>
    ```
- Delete nodes
  ```
  kubectl delete node <node-name>
  ```

- Check if cluster level resources still exist
  ```
  kubectl get ingress -A
  kubectl get svc -A
  kubectl get pv
  kubectl get pvc
  kubectl get hpa -A
  ```

  - Delete if still
    ```
    kubectl delete ingress --all -A
    kubectl delete svc --all -A
    kubectl delete pv --all
    kubectl delete pvc --all
    kubectl delete hpa --all -A
    ```

- Destroy Terraform infrastructure:
  ```bash
  terraform destroy
  ```

---

## Troubleshooting Summary

- **`kubectl get nodes` hangs** → Cluster endpoint not reachable (check VPC, endpoint, SGs).
- **“client must provide credentials”** → Add bastion IAM role to aws-auth ConfigMap.
- **Docker permission denied** → Add `ssm-user` to `docker` group.
- **ECR auth error** → Use `sudo` for both login and push.
- **ECR repo not found** → Create the repo first.
- **YAML parse error** → Fix indentation under `ports:` or `env:`.
- **Namespace stuck in Terminating** → Finalizer or AWS load balancer cleanup delay.

---

## Optional Useful Commands

- Check cluster info:
  ```bash
  kubectl cluster-info
  ```
- List pods in all namespaces:
  ```bash
  kubectl get pods -A
  ```
- Delete all demo resources manually:
  ```bash
  kubectl delete all --all -n demo
  ```