#!/bin/bash
set -e

REGION="us-east-1"
VPCS=("vpc-03fc8cd84d5fcd323" "vpc-036162bbc019c34cc" "vpc-0703381b693cc4696" "vpc-0bc239fb1d508570c")

echo "=== Cleaning up orphaned site-a resources ==="

# Function to delete VPC and all dependencies
delete_vpc() {
  local VPC_ID=$1
  echo ""
  echo "🧹 Cleaning VPC: $VPC_ID"
  
  # 1. Delete NAT Gateways
  echo "  → Deleting NAT Gateways..."
  NAT_GWS=$(aws ec2 describe-nat-gateways --region $REGION \
    --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
    --query 'NatGateways[*].NatGatewayId' --output text)
  
  for nat in $NAT_GWS; do
    echo "    Deleting NAT Gateway: $nat"
    aws ec2 delete-nat-gateway --region $REGION --nat-gateway-id $nat
  done
  
  # Wait for NAT gateways to be deleted
  if [ -n "$NAT_GWS" ]; then
    echo "  → Waiting for NAT Gateways to delete (this may take 2-3 minutes)..."
    sleep 30
    for nat in $NAT_GWS; do
      aws ec2 wait nat-gateway-deleted --region $REGION --nat-gateway-ids $nat 2>/dev/null || true
    done
  fi
  
  # 2. Release Elastic IPs
  echo "  → Releasing Elastic IPs..."
  EIPS=$(aws ec2 describe-addresses --region $REGION \
    --filters "Name=domain,Values=vpc" \
    --query 'Addresses[*].AllocationId' --output text)
  
  for eip in $EIPS; do
    echo "    Releasing EIP: $eip"
    aws ec2 release-address --region $REGION --allocation-id $eip 2>/dev/null || true
  done
  
  # 3. Delete Security Groups (except default)
  echo "  → Deleting Security Groups..."
  SGS=$(aws ec2 describe-security-groups --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
  
  for sg in $SGS; do
    echo "    Deleting Security Group: $sg"
    aws ec2 delete-security-group --region $REGION --group-id $sg 2>/dev/null || true
  done
  
  # 4. Detach and Delete Internet Gateways
  echo "  → Deleting Internet Gateways..."
  IGWS=$(aws ec2 describe-internet-gateways --region $REGION \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[*].InternetGatewayId' --output text)
  
  for igw in $IGWS; do
    echo "    Detaching IGW: $igw"
    aws ec2 detach-internet-gateway --region $REGION --internet-gateway-id $igw --vpc-id $VPC_ID
    echo "    Deleting IGW: $igw"
    aws ec2 delete-internet-gateway --region $REGION --internet-gateway-id $igw
  done
  
  # 5. Delete Subnets
  echo "  → Deleting Subnets..."
  SUBNETS=$(aws ec2 describe-subnets --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[*].SubnetId' --output text)
  
  for subnet in $SUBNETS; do
    echo "    Deleting Subnet: $subnet"
    aws ec2 delete-subnet --region $REGION --subnet-id $subnet
  done
  
  # 6. Delete Route Tables (except main)
  echo "  → Deleting Route Tables..."
  RTS=$(aws ec2 describe-route-tables --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
  
  for rt in $RTS; do
    echo "    Deleting Route Table: $rt"
    aws ec2 delete-route-table --region $REGION --route-table-id $rt 2>/dev/null || true
  done
  
  # 7. Delete VPC
  echo "  → Deleting VPC: $VPC_ID"
  aws ec2 delete-vpc --region $REGION --vpc-id $VPC_ID
  echo "  ✅ VPC $VPC_ID deleted"
}

# Delete all VPCs
for vpc in "${VPCS[@]}"; do
  delete_vpc "$vpc"
done

# Delete IAM roles
echo ""
echo "🧹 Cleaning up IAM roles..."
IAM_ROLES=$(aws iam list-roles --query 'Roles[?contains(RoleName, `mq-ha-site-a`)].RoleName' --output text)

for role in $IAM_ROLES; do
  echo "  → Deleting IAM Role: $role"
  
  # Detach managed policies
  POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[*].PolicyArn' --output text)
  for policy in $POLICIES; do
    echo "    Detaching policy: $policy"
    aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
  done
  
  # Delete inline policies
  INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[*]' --output text)
  for policy in $INLINE_POLICIES; do
    echo "    Deleting inline policy: $policy"
    aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
  done
  
  # Delete role
  aws iam delete-role --role-name "$role"
  echo "  ✅ Deleted role: $role"
done

echo ""
echo "✅ Cleanup complete for site-a!"
