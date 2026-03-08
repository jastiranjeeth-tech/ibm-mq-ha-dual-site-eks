# AWS Cost Estimate for Dual-Site MQ HA Setup

## Infrastructure Components

### Site A (us-east-1)
| Component | Quantity | Unit Cost | Hourly Cost |
|-----------|----------|-----------|-------------|
| EKS Cluster | 1 | $0.10/hour | $0.10 |
| t3.medium nodes | 3 | $0.0416/hour | $0.1248 |
| NAT Gateway | 1 | $0.045/hour | $0.045 |
| EBS gp3 volumes (10GB each) | 3 | $0.08/GB/month | $0.0033 |
| Network Load Balancer | 1 | $0.0225/hour | $0.0225 |
| **Subtotal per hour** | | | **$0.2956** |

### Site B (us-west-2)
| Component | Quantity | Unit Cost | Hourly Cost |
|-----------|----------|-----------|-------------|
| EKS Cluster | 1 | $0.10/hour | $0.10 |
| t3.medium nodes | 3 | $0.0416/hour | $0.1248 |
| NAT Gateway | 1 | $0.045/hour | $0.045 |
| EBS gp3 volumes (10GB each) | 3 | $0.08/GB/month | $0.0033 |
| Network Load Balancer | 1 | $0.0225/hour | $0.0225 |
| **Subtotal per hour** | | | **$0.2956** |

### Global Resources
| Component | Quantity | Unit Cost | Hourly Cost |
|-----------|----------|-----------|-------------|
| Route53 Health Checks | 2 | $0.50/month each | $0.0014 |
| Route53 Hosted Zone | 1 | $0.50/month | $0.0007 |
| **Subtotal per hour** | | | **$0.0021** |

## Total Cost Breakdown

| Duration | Total Cost |
|----------|------------|
| **Per Hour** | **$0.59** |
| **4 Hours** | **$2.37** |
| **8 Hours** | **$4.74** |
| **24 Hours (1 Day)** | **$14.22** |
| **168 Hours (1 Week)** | **$99.54** |
| **730 Hours (1 Month)** | **$431.70** |

## Cost Optimization Options

### 1. Use Spot Instances (Currently Disabled)
- **Savings**: ~70% on EC2 costs
- **Risk**: Potential interruption
- **Enable in**: `terraform/sites/site-*/variables.tf` → set `enable_spot_instances = true`
- **New 4-hour cost**: ~$1.80 (saves $0.57)

### 2. Single NAT Gateway Architecture (Currently Enabled)
- Already using single NAT gateway per VPC
- Saves ~$0.09/hour vs multi-AZ NAT

### 3. Reduce Node Count for Testing
- Run 1 node per site instead of 3 (MQ HA requires min 3)
- Not recommended for HA testing

### 4. Run Only One Site
- Half the cost: ~$1.18 for 4 hours
- Loses multi-site failover capability

### 5. Use t3.small Instead of t3.medium
- t3.small: $0.0208/hour (half the cost)
- **Savings**: ~$0.37 for 4 hours
- **Risk**: May not have enough resources for MQ pods

## Data Transfer Costs (Additional)

Not included in above estimates:
- **Cross-region replication** (if implemented): $0.02/GB
- **Internet egress**: First 1GB free, then $0.09/GB
- **NLB data processing**: $0.006/GB

For testing (4 hours), data transfer will likely be minimal (<$0.10).

## Recommended Test Configuration

**For 4-hour testing:**
- Keep current setup: **$2.37**
- Enable Spot instances: **$1.80**
- Test one site only: **$1.18**

## Cost Monitoring Commands

```bash
# Check current AWS costs (requires AWS CLI)
aws ce get-cost-and-usage \
  --time-period Start=2026-03-07,End=2026-03-08 \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=SERVICE

# Set up billing alert (one-time)
aws cloudwatch put-metric-alarm \
  --alarm-name eks-cost-alert \
  --alarm-description "Alert when EKS costs exceed $10" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold
```

## Clean Up After Testing

**IMPORTANT**: Run terraform destroy to avoid ongoing charges:

```bash
# From GitHub Actions
# Go to Actions → Run workflow → Select "destroy-both"

# Or locally
cd terraform/sites/site-a
terraform destroy -auto-approve

cd ../site-b
terraform destroy -auto-approve
```

**Remember**: Even stopped resources incur costs (EBS volumes, NAT Gateways, Load Balancers).
