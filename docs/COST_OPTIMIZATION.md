# Cost Optimization Guide

This document provides detailed strategies for minimizing AWS costs while running the EKS demo.

## Current Cost Breakdown

### Monthly Costs (Running 24/7)

| Resource | Configuration | Monthly Cost | Notes |
|----------|--------------|--------------|-------|
| EKS Control Plane | 1 cluster | $72.00 | Fixed cost per cluster |
| NAT Gateway | 1 in single AZ | $32.40 | $0.045/hour |
| EC2 Worker Nodes | 2x t3.small spot | $8-12 | ~70% cheaper than on-demand |
| Application Load Balancer | 1 ALB | $16.20 | $0.0225/hour base |
| EBS Volumes | 2x 20GB gp3 | $3.20 | $0.08/GB-month |
| Data Transfer | Minimal | $2-5 | Varies with usage |
| ECR Storage | <1GB images | $0.10 | $0.10/GB-month |
| **TOTAL (Running)** | | **~$134-141** | |
| **TOTAL (Destroyed)** | | **~$0.10-1.00** | Only ECR remains |

## Optimization Strategies

### 1. Destroy When Not in Use (Highest Impact)

**Savings: ~$133/month**

```bash
# Quick teardown
./cleanup.sh

# Or manual
cd infra && terraform destroy

# Rebuild time: ~15-20 minutes
cd infra && terraform apply
```

**Best For**: 
- Demo environments
- Learning/training
- Infrequent use (< 8 hours/day)

**ROI**: If using < 6 hours/day, destroy saves 75% of costs

### 2. Use Spot Instances (Already Implemented)

**Savings: ~$20-25/month vs on-demand**

Current configuration in `infra/modules/eks/main.tf`:
```hcl
capacity_type = "SPOT"
```

**Trade-offs**:
- May be interrupted with 2-minute notice
- Good for stateless workloads
- Not recommended for production

### 3. Reduce Node Count

**Savings: ~$4-6/month per node**

Edit `infra/terraform.tfvars`:
```hcl
node_desired_size = 1  # Reduced from 2
node_min_size     = 1
```

**Trade-offs**:
- No high availability
- Single point of failure
- Good enough for solo demos

### 4. Use Smaller Instance Types

**Current**: t3.small (2 vCPU, 2GB RAM)

**Alternative**: t3.micro (2 vCPU, 1GB RAM)

Edit `infra/terraform.tfvars`:
```hcl
node_instance_types = ["t3.micro"]
```

**Savings**: ~$3-5/month
**Trade-offs**: 
- May run out of memory with multiple pods
- Limited to very simple workloads

### 5. Remove NAT Gateway (Aggressive Savings)

**Savings: ~$32/month**

**Option A**: Use Public Subnets for Nodes
- Nodes get public IPs
- Direct internet access
- Less secure

**Option B**: Use VPC Endpoints
- More setup complexity
- Cost depends on data transfer
- Breakeven around 5-10GB/month

**Implementation**: Requires infrastructure redesign

### 6. Skip EKS (Not Recommended for This Demo)

**Alternative**: Use ECS or plain EC2 with k3s/microk8s

**Savings**: $72/month (EKS control plane)
**Trade-offs**:
- Defeats purpose of EKS demo
- More maintenance
- Missing EKS-specific features

### 7. Use Fargate for Nodes (Alternative Approach)

**Cost Model**: Pay per pod (vCPU-hour + GB-hour)

**Example**: 2 pods, 0.25 vCPU, 0.5GB RAM each
- Cost: ~$8-10/month
- Removes EC2 node costs
- Simpler management

**Requires**: Different Terraform configuration

### 8. Optimize Load Balancer

**Option A**: Use NodePort Instead of ALB
```bash
# Edit service.yaml
type: NodePort  # instead of Ingress
```
**Savings**: $16/month
**Trade-offs**: 
- No pretty URLs
- Manual port management
- Less production-like

**Option B**: Use NLB Instead of ALB
- Slightly cheaper (~$14 vs $16/month)
- Limited to Layer 4
- No HTTP path routing

### 9. Schedule Start/Stop

**Savings: Proportional to downtime**

**Example**: Run 9am-6pm weekdays only
- Runtime: 45 hours/week vs 168 hours/week
- Savings: ~73% of variable costs
- Monthly: ~$95 instead of ~$134

**Implementation**:
```bash
# Startup script
cd infra && terraform apply -auto-approve

# Shutdown script
./cleanup.sh
```

Add to cron or use AWS Lambda for scheduling.

### 10. Multi-Tenant Cluster

**Scenario**: Multiple demos in one cluster

**Savings**: Share fixed costs (EKS, NAT, ALB)
- First app: $134/month
- Second app: ~$8/month (just nodes)
- Per-app cost drops significantly

**Implementation**: Use Kubernetes namespaces

## Cost Monitoring

### Set Up AWS Budgets

```bash
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json
```

### Track Costs by Tag

All resources are tagged:
```hcl
tags = {
  Project     = "eks-demo"
  Environment = "demo"
  ManagedBy   = "terraform"
}
```

Use AWS Cost Explorer to filter by these tags.

### Enable Cost Anomaly Detection

```bash
aws ce create-anomaly-monitor \
  --anomaly-monitor Name=EKS-Demo-Monitor,MonitorType=DIMENSIONAL \
  --monitor-dimension=SERVICE
```

## Recommended Configurations by Use Case

### Solo Learning (Minimal Budget)

```hcl
node_desired_size   = 1
node_instance_types = ["t3.micro"]
# Skip ALB - use NodePort
# Destroy daily when done
```
**Monthly**: ~$5-10 (assuming 2-3 hours/day use)

### Weekly Demos

```hcl
node_desired_size   = 2
node_instance_types = ["t3.small"]
# Use ALB for professional presentation
# Destroy between demos
```
**Monthly**: ~$20-30 (assuming 8 hours/week use)

### Shared Team Environment

```hcl
node_desired_size   = 2
node_instance_types = ["t3.small"]
# Keep running during business hours
# Destroy nights/weekends
```
**Monthly**: ~$50-70 (45 hours/week)

### Current Configuration (Default)

```hcl
node_desired_size   = 2
node_instance_types = ["t3.small"]
# Full featured demo environment
```
**Monthly**: ~$134-141 (24/7)

## Cost Comparison

| Configuration | Monthly Cost | Best For |
|--------------|--------------|----------|
| Destroyed (only ECR) | $0.10-1 | Not in use |
| Minimal (t3.micro, 1 node) | $5-10 | Solo learning, 2-3 hrs/day |
| Weekly demos | $20-30 | Team demos, 8 hrs/week |
| Business hours | $50-70 | Shared team, 45 hrs/week |
| **Current (24/7)** | **$134-141** | **Full-featured demo** |
| Production-like (multi-AZ) | $300-400 | Don't do this for demos! |

## Automated Cost Management

### Daily Destroy Script (Cron)

```bash
# Add to crontab (destroy at 6 PM daily)
0 18 * * * cd /path/to/eks-demo && ./cleanup.sh >> cleanup.log 2>&1
```

### Weekend Destroyer

```bash
# Destroy Friday evening, rebuild Monday morning
0 18 * * 5 cd /path/to/eks-demo && ./cleanup.sh
0 8 * * 1 cd /path/to/eks-demo/infra && terraform apply -auto-approve
```

## Conclusion

**Best Practice for Personal Demos**:
1. Use current configuration (good balance)
2. Run `./cleanup.sh` when done for the day
3. Rebuild when needed (~15-20 min)
4. **Average monthly cost: $5-20** depending on usage

**Remember**: 
- EKS control plane is the largest fixed cost ($72/month)
- NAT Gateway is second largest ($32/month)
- Spot instances provide best value for worker nodes
- Destroy infrastructure when not demoing to save 99% of costs

