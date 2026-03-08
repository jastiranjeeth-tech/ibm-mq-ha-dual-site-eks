#!/bin/bash
set -euo pipefail

# Import AWS resources into Terraform state
# Usage: ./import-aws-resources.sh [site] [region]
# Example: ./import-aws-resources.sh site-a us-east-1

SITE=${1:-site-a}
REGION=${2:-us-east-1}

if [ "$SITE" != "site-a" ] && [ "$SITE" != "site-b" ]; then
  echo "❌ Invalid site. Use 'site-a' or 'site-b'"
  exit 1
fi

echo "=========================================="
echo "Importing AWS Resources for: $SITE"
echo "Region: $REGION"
echo "=========================================="
echo ""

# Initialize Terraform
echo "Initializing Terraform..."
terraform -chdir=terraform/sites/${SITE} init

# Get cluster name
CLUSTER_NAME="mq-ha-${SITE}"
echo ""
echo "Looking for cluster: $CLUSTER_NAME"

# Check if cluster exists
if ! aws eks describe-cluster --name $CLUSTER_NAME --region $REGION 2>/dev/null; then
  echo "❌ Cluster $CLUSTER_NAME not found in $REGION"
  exit 1
fi

echo "✅ Found cluster $CLUSTER_NAME"
echo ""

# Import EKS Cluster
echo "STEP 1: Importing EKS Cluster"
echo "=========================================="
terraform -chdir=terraform/sites/${SITE} import \
  'module.eks.aws_eks_cluster.this[0]' \
  $CLUSTER_NAME || echo "⚠️  Cluster may already be in state"
echo ""

# Get VPC ID from cluster
echo "STEP 2: Finding VPC..."
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
echo "VPC ID: $VPC_ID"

# Import VPC
echo "Importing VPC..."
terraform -chdir=terraform/sites/${SITE} import \
  'module.vpc.aws_vpc.this[0]' \
  $VPC_ID || echo "⚠️  VPC may already be in state"
echo ""

# Import Internet Gateway
echo "STEP 3: Importing Internet Gateway..."
IGW_ID=$(aws ec2 describe-internet-gateways --region $REGION \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query 'InternetGateways[0].InternetGatewayId' --output text)

if [ "$IGW_ID" != "None" ] && [ ! -z "$IGW_ID" ]; then
  echo "IGW ID: $IGW_ID"
  terraform -chdir=terraform/sites/${SITE} import \
    'module.vpc.aws_internet_gateway.this[0]' \
    $IGW_ID || echo "⚠️  IGW may already be in state"
else
  echo "⚠️  No Internet Gateway found"
fi
echo ""

# Import NAT Gateway
echo "STEP 4: Importing NAT Gateway..."
NATGW=$(aws ec2 describe-nat-gateways --region $REGION \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'NatGateways[0].[NatGatewayId,State]' --output text)

if [ ! -z "$NATGW" ]; then
  NATGW_ID=$(echo $NATGW | awk '{print $1}')
  NATGW_STATE=$(echo $NATGW | awk '{print $2}')
  echo "NAT Gateway ID: $NATGW_ID (State: $NATGW_STATE)"
  terraform -chdir=terraform/sites/${SITE} import \
    'module.vpc.aws_nat_gateway.this[0]' \
    $NATGW_ID || echo "⚠️  NAT Gateway may already be in state"
else
  echo "⚠️  No NAT Gateway found"
fi
echo ""

# Import Subnets
echo "STEP 5: Importing Subnets..."
SUBNETS=$(aws ec2 describe-subnets --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].SubnetId' --output text)

SUBNET_INDEX=0
for subnet in $SUBNETS; do
  echo "Importing subnet $subnet (index: $SUBNET_INDEX)"
  terraform -chdir=terraform/sites/${SITE} import \
    "module.vpc.aws_subnet.private[$SUBNET_INDEX]" \
    $subnet 2>/dev/null || terraform -chdir=terraform/sites/${SITE} import \
    "module.vpc.aws_subnet.public[$SUBNET_INDEX]" \
    $subnet 2>/dev/null || echo "⚠️  Subnet may already be in state"
  SUBNET_INDEX=$((SUBNET_INDEX + 1))
done
echo ""

# Import Node Group
echo "STEP 6: Importing EKS Managed Node Group..."
NODE_GROUP_NAME="${CLUSTER_NAME}-ng"
terraform -chdir=terraform/sites/${SITE} import \
  'module.eks.aws_eks_node_group.this["mq_nodes"]' \
  "${CLUSTER_NAME}:${NODE_GROUP_NAME}" || echo "⚠️  Node Group may already be in state"
echo ""

# Import Node IAM Role
echo "STEP 7: Importing Node IAM Role..."
NODE_ROLE_NAME="${CLUSTER_NAME}-node-role"
terraform -chdir=terraform/sites/${SITE} import \
  'module.eks.module.eks_managed_node_group["mq_nodes"].aws_iam_role.this[0]' \
  $NODE_ROLE_NAME || echo "⚠️  Node Role may already be in state"
echo ""

# Import Security Groups
echo "STEP 8: Importing Security Groups..."
SG_IDS=$(aws ec2 describe-security-groups --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)

SG_INDEX=0
for sg in $SG_IDS; do
  SG_NAME=$(aws ec2 describe-security-groups --group-ids $sg --region $REGION --query 'SecurityGroups[0].GroupName' --output text)
  echo "Importing security group $sg ($SG_NAME)"
  terraform -chdir=terraform/sites/${SITE} import \
    "module.eks.aws_security_group.node[0]" \
    $sg 2>/dev/null || true
  SG_INDEX=$((SG_INDEX + 1))
done
echo ""

# Final state check
echo "=========================================="
echo "IMPORT COMPLETE"
echo "=========================================="
echo ""
echo "Resources in Terraform state:"
terraform -chdir=terraform/sites/${SITE} state list
echo ""
echo "✅ Import completed successfully!"
echo ""
echo "Next steps:"
echo "1. Run 'terraform -chdir=terraform/sites/${SITE} plan' to verify"
echo "2. If there are changes, review them carefully"
echo "3. Run 'terraform -chdir=terraform/sites/${SITE} apply' if needed"
echo ""
