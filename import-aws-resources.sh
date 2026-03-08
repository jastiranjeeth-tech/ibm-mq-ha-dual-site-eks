#!/bin/bash
set -euo pipefail

# Import AWS resources into Terraform state
# Usage: ./import-aws-resources.sh [site] [region]
# Example: ./import-aws-resources.sh site-a us-east-1

SITE=${1:-site-a}
REGION=${2:-us-east-1}
TF_STATE_KEY_PREFIX=${TF_STATE_KEY_PREFIX:-mqha-eks}

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
if [ -n "${TF_STATE_BUCKET:-}" ] && [ -n "${TF_STATE_REGION:-}" ] && [ -n "${TF_LOCK_TABLE:-}" ]; then
  echo "Using remote backend: s3://${TF_STATE_BUCKET}/${TF_STATE_KEY_PREFIX}/${SITE}/terraform.tfstate"
  terraform -chdir=terraform/sites/${SITE} init \
    -backend-config="bucket=${TF_STATE_BUCKET}" \
    -backend-config="key=${TF_STATE_KEY_PREFIX}/${SITE}/terraform.tfstate" \
    -backend-config="region=${TF_STATE_REGION}" \
    -backend-config="dynamodb_table=${TF_LOCK_TABLE}" \
    -backend-config="encrypt=true"
else
  echo "Using local backend (set TF_STATE_BUCKET, TF_STATE_REGION, TF_LOCK_TABLE to use remote backend)"
  terraform -chdir=terraform/sites/${SITE} init
fi

# Get cluster name
CLUSTER_NAME="mq-ha-${SITE}"
echo ""
echo "Looking for cluster: $CLUSTER_NAME"

# Import common resources that might survive partial destroy
echo "STEP 0: Importing common pre-existing resources (if any)"
echo "=========================================="

KMS_ALIAS="alias/eks/${CLUSTER_NAME}"
LOG_GROUP="/aws/eks/${CLUSTER_NAME}/cluster"
NODE_ROLE_NAME="${CLUSTER_NAME}-node-role"

if aws kms describe-key --key-id "$KMS_ALIAS" --region "$REGION" >/dev/null 2>&1; then
  echo "Importing KMS alias: $KMS_ALIAS"
  terraform -chdir=terraform/sites/${SITE} import \
    'module.eks.module.kms.aws_kms_alias.this["cluster"]' \
    "$KMS_ALIAS" || echo "⚠️  KMS alias may already be in state"
else
  echo "KMS alias not found: $KMS_ALIAS"
fi

if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$REGION" --query 'logGroups[?logGroupName==`'"$LOG_GROUP"'`].logGroupName' --output text | grep -q "$LOG_GROUP"; then
  echo "Importing CloudWatch log group: $LOG_GROUP"
  terraform -chdir=terraform/sites/${SITE} import \
    'module.eks.aws_cloudwatch_log_group.this[0]' \
    "$LOG_GROUP" || echo "⚠️  Log group may already be in state"
else
  echo "Log group not found: $LOG_GROUP"
fi

if aws iam get-role --role-name "$NODE_ROLE_NAME" >/dev/null 2>&1; then
  echo "Importing node IAM role: $NODE_ROLE_NAME"
  terraform -chdir=terraform/sites/${SITE} import \
    'module.eks.module.eks_managed_node_group["mq_nodes"].aws_iam_role.this[0]' \
    "$NODE_ROLE_NAME" || echo "⚠️  Node role may already be in state"
else
  echo "Node IAM role not found: $NODE_ROLE_NAME"
fi

echo ""

# Check if cluster exists for deep import
if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "⚠️  Cluster $CLUSTER_NAME not found in $REGION"
  echo "✅ Completed common resource import only."
  echo ""
  echo "Current state resources:"
  terraform -chdir=terraform/sites/${SITE} state list || true
  exit 0
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
