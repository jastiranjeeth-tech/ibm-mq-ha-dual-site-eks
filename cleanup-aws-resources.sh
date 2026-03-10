#!/bin/bash
set -euo pipefail

# Cleanup orphaned AWS resources script
# Usage: ./cleanup-aws-resources.sh [region] [site]
# Example: ./cleanup-aws-resources.sh us-east-1 site-a

REGION=${1:-us-east-1}
SITE=${2:-site-a}

echo "=========================================="
echo "AWS Resource Cleanup for: $SITE ($REGION)"
echo "=========================================="
echo ""

# Function to retry command
retry_destroy() {
  local attempt=1
  local max_attempts=3
  
  while [ $attempt -le $max_attempts ]; do
    echo "Attempt $attempt/$max_attempts..."
    if terraform -chdir=terraform/sites/${SITE} destroy -auto-approve; then
      return 0
    fi
    attempt=$((attempt + 1))
    if [ $attempt -le $max_attempts ]; then
      echo "Destroy failed, waiting 10 seconds before retry..."
      sleep 10
    fi
  done
  return 1
}

# Step 0: Initialize Terraform backend
echo "STEP 0: Initializing Terraform Backend"
echo "=========================================="
terraform -chdir=terraform/sites/${SITE} init -upgrade
echo ""

# Step 1: Show what will be deleted
echo "STEP 1: Resources that will be DESTROYED"
echo "=========================================="
terraform -chdir=terraform/sites/${SITE} plan -destroy || true
echo ""

# Step 2: Run destroy
echo "STEP 2: Running Terraform Destroy"
echo "=========================================="
retry_destroy
echo ""

# Step 3: Verify state file
echo "STEP 3: Verifying Terraform State"
echo "=========================================="
RESOURCE_COUNT=$(terraform -chdir=terraform/sites/${SITE} state list 2>/dev/null | wc -l || echo "0")
echo "Remaining resources in state: $RESOURCE_COUNT"

if [ $RESOURCE_COUNT -gt 0 ]; then
  echo ""
  echo "⚠️  WARNING: Found $RESOURCE_COUNT remaining resources"
  echo "Resources still in state:"
  terraform -chdir=terraform/sites/${SITE} state list
  echo ""
  echo "Running destroy again..."
  retry_destroy
  echo ""
  RESOURCE_COUNT=$(terraform -chdir=terraform/sites/${SITE} state list 2>/dev/null | wc -l || echo "0")
  echo "Resources after second destroy: $RESOURCE_COUNT"
else
  echo "✅ State file is clean - all resources destroyed"
fi
echo ""

# Step 4: Verify AWS resources
echo "STEP 4: Verifying AWS Resources Deleted"
echo "=========================================="

echo ""
echo "Checking EKS Clusters..."
EKS_CLUSTERS=$(aws eks list-clusters --region $REGION --query 'clusters[?contains(@, `mq-ha`)]' --output text)
if [ -z "$EKS_CLUSTERS" ]; then
  echo "✅ No EKS clusters found"
else
  echo "⚠️  Remaining EKS clusters: $EKS_CLUSTERS"
fi

echo ""
echo "Checking VPCs..."
VPC_INFO=$(aws ec2 describe-vpcs --region $REGION --query 'Vpcs[?Tags[?Key==`Name`].Value|contains(@, `mq-ha`)].{VpcId:VpcId, Name:Tags[?Key==`Name`].Value|[0]}' --output text)
if [ -z "$VPC_INFO" ]; then
  echo "✅ No mq-ha VPCs found"
else
  echo "⚠️  Remaining VPCs:"
  echo "$VPC_INFO"
fi

echo ""
echo "Checking NAT Gateways..."
NGWS=$(aws ec2 describe-nat-gateways --region $REGION --query 'NatGateways[?State==`available`].[NatGatewayId,CreateTime]' --output text)
if [ -z "$NGWS" ]; then
  echo "✅ No active NAT Gateways found"
else
  echo "⚠️  Active NAT Gateways:"
  aws ec2 describe-nat-gateways --region $REGION --query 'NatGateways[?State==`available`].[NatGatewayId,State,CreateTime]' --output table
fi

echo ""
echo "Checking Network Interfaces..."
ENIS=$(aws ec2 describe-network-interfaces --region $REGION --query 'NetworkInterfaces[?Association.IpOwnerId!=`amazon`].NetworkInterfaceId' --output text | wc -w)
echo "Available ENIs: $ENIS"

echo ""
echo "Checking Security Groups..."
SG_COUNT=$(aws ec2 describe-security-groups --region $REGION --query 'SecurityGroups[?contains(GroupName, `mq-ha`) || contains(GroupDescription, `mq-ha`)].GroupId' --output text | wc -w)
if [ $SG_COUNT -gt 0 ]; then
  echo "⚠️  Found $SG_COUNT security groups with 'mq-ha'"
  aws ec2 describe-security-groups --region $REGION --query 'SecurityGroups[?contains(GroupName, `mq-ha`) || contains(GroupDescription, `mq-ha`)].{GroupId:GroupId,GroupName:GroupName}' --output table
else
  echo "✅ No mq-ha security groups found"
fi

echo ""
echo "=========================================="
echo "Cleanup Summary"
echo "=========================================="
echo "✅ Destroy completed for $SITE"
echo "📊 Check the output above for any remaining resources"
echo ""
echo "Next steps:"
echo "1. If resources remain, they may be attached to other resources"
echo "2. Check AWS console for manual cleanup if needed"
echo "3. Remove Terraform backend state: terraform -chdir=terraform/sites/$SITE state rm <resource>"
echo ""
