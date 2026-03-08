# Check Resources Before Destroy

## Terraform State

```bash
# Check current terraform state for site-a
terraform -chdir=terraform/sites/site-a state list

# Get detailed info on all resources in site-a
terraform -chdir=terraform/sites/site-a state show

# Same for site-b
terraform -chdir=terraform/sites/site-b state list
terraform -chdir=terraform/sites/site-b state show
```

## AWS CLI Commands to Verify Created Resources

### EKS Clusters
```bash
# List all EKS clusters in us-east-1
aws eks list-clusters --region us-east-1

# List all EKS clusters in us-west-2
aws eks list-clusters --region us-west-2

# Get details on specific cluster
aws eks describe-cluster --name mq-ha-site-a --region us-east-1
aws eks describe-cluster --name mq-ha-site-b --region us-west-2
```

### EC2 Resources
```bash
# List all VPCs
aws ec2 describe-vpcs --region us-east-1 --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table

# List all NAT Gateways
aws ec2 describe-nat-gateways --region us-east-1 --output table

# List all Load Balancers
aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[*].[LoadBalancerName,LoadBalancerArn]' --output table
```

### IAM Resources
```bash
# List all roles created for this
aws iam list-roles --query 'Roles[?contains(RoleName, `mq-ha`)].RoleName' --output table
```

### EBS Volumes
```bash
# List EBS volumes in us-east-1
aws ec2 describe-volumes --region us-east-1 --query 'Volumes[*].[VolumeId,Size,State,Tags[?Key==`Name`].Value|[0]]' --output table
```

### Terraform Plan Before Destroy
```bash
# See what will be destroyed
terraform -chdir=terraform/sites/site-a plan -destroy

# Or for actual destroy preview
terraform -chdir=terraform/sites/site-a destroy -auto-approve -lock=false (DON'T RUN - just shows preview)
```

## Quick Summary Command

```bash
#!/bin/bash

echo "=== Checking Resources in us-east-1 (Site A) ==="
echo ""
echo "EKS Clusters:"
aws eks list-clusters --region us-east-1 --query 'clusters' --output text

echo ""
echo "VPCs:"
aws ec2 describe-vpcs --region us-east-1 --query 'Vpcs[?Tags[?Key==`Name`].Value|contains(@, `mq-ha`)].{VpcId:VpcId, CidrBlock:CidrBlock, Name:Tags[?Key==`Name`].Value|[0]}' --output table

echo ""
echo "NAT Gateways:"
aws ec2 describe-nat-gateways --region us-east-1 --query 'NatGateways[?State==`available`].[NatGatewayId,PublicIpAddress,State]' --output table

echo ""
echo "Network Interfaces:"
aws ec2 describe-network-interfaces --region us-east-1 --query 'NetworkInterfaces[?Association.IpOwnerId!=`amazon`].[NetworkInterfaceId,Status,PrivateIpAddress]' --output table

echo ""
echo "=== Checking Resources in us-west-2 (Site B) ==="
echo ""
echo "EKS Clusters:"
aws eks list-clusters --region us-west-2 --query 'clusters' --output text

echo ""
echo "VPCs:"
aws ec2 describe-vpcs --region us-west-2 --query 'Vpcs[?Tags[?Key==`Name`].Value|contains(@, `mq-ha`)].{VpcId:VpcId, CidrBlock:CidrBlock, Name:Tags[?Key==`Name`].Value|[0]}' --output table
```

## Check Kubernetes Resources

If clusters were deployed, check what's inside:

```bash
# Get kubeconfig for site-a
CLUSTER_NAME=$(terraform -chdir=terraform/sites/site-a output -raw cluster_name)
aws eks update-kubeconfig --name $CLUSTER_NAME --region us-east-1

# Check MQ pods
kubectl get pods -n ibm-mq
kubectl get svc -n ibm-mq
kubectl get pvc -n ibm-mq

# Check nodes
kubectl get nodes
```

## Before You Destroy

**Save this info first:**
```bash
# Export current state
terraform -chdir=terraform/sites/site-a state pull > site-a-state.json
terraform -chdir=terraform/sites/site-b state pull > site-b-state.json

# Export all AWS resources
aws ec2 describe-instances --region us-east-1 > site-a-instances.json
aws ec2 describe-instances --region us-west-2 > site-b-instances.json
```

Then run destroy:
```bash
# Option 1: Via GitHub Actions (recommended)
# Go to Actions → Run workflow → Select "destroy-site-a" or "destroy-both"

# Option 2: Locally
cd terraform/sites/site-a
terraform destroy -auto-approve
cd ../site-b
terraform destroy -auto-approve
```
