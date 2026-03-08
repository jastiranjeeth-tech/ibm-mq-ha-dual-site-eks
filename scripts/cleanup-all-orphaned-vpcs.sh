#!/bin/bash
set -e

echo "=== Comprehensive cleanup of all orphaned VPCs ==="

# Function to clean up a VPC completely
cleanup_vpc() {
  local VPC_ID=$1
  local REGION=$2
  
  echo ""
  echo "🧹 Cleaning VPC: $VPC_ID in $REGION"
  
  # 1. Revoke all security group rules and delete security groups
  echo "  → Processing Security Groups..."
  SGS=$(aws ec2 describe-security-groups --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
  
  for sg in $SGS; do
    echo "    Revoking rules from $sg..."
    
    # Revoke ingress rules
    INGRESS=$(aws ec2 describe-security-groups --region $REGION --group-ids $sg \
      --query 'SecurityGroups[0].IpPermissions' --output json)
    if [ "$INGRESS" != "[]" ]; then
      echo "$INGRESS" > /tmp/ingress-$sg.json
      aws ec2 revoke-security-group-ingress --region $REGION --group-id $sg \
        --ip-permissions file:///tmp/ingress-$sg.json 2>/dev/null || true
    fi
    
    # Revoke egress rules
    EGRESS=$(aws ec2 describe-security-groups --region $REGION --group-ids $sg \
      --query 'SecurityGroups[0].IpPermissionsEgress' --output json)
    if [ "$EGRESS" != "[]" ]; then
      echo "$EGRESS" > /tmp/egress-$sg.json
      aws ec2 revoke-security-group-egress --region $REGION --group-id $sg \
        --ip-permissions file:///tmp/egress-$sg.json 2>/dev/null || true
    fi
    
    # Delete security group
    echo "    Deleting $sg..."
    aws ec2 delete-security-group --region $REGION --group-id $sg 2>/dev/null || true
  done
  
  # 2. Delete VPC
  echo "  → Deleting VPC: $VPC_ID"
  aws ec2 delete-vpc --region $REGION --vpc-id $VPC_ID && echo "  ✅ VPC deleted" || echo "  ⚠️  VPC deletion failed - may have remaining dependencies"
}

# Site-A VPCs (us-east-1)
echo ""
echo "=== Site-A VPCs (us-east-1) ==="
SITE_A_VPCS=("vpc-03fc8cd84d5fcd323" "vpc-036162bbc019c34cc" "vpc-0703381b693cc4696" "vpc-0bc239fb1d508570c")
for vpc in "${SITE_A_VPCS[@]}"; do
  cleanup_vpc "$vpc" "us-east-1"
done

# Site-B VPCs (us-west-2)
echo ""
echo "=== Site-B VPCs (us-west-2) ==="
SITE_B_VPCS=("vpc-0937623017216bfe5" "vpc-054f0dba7e3c9a0e7" "vpc-06c18093eb7f1081b")
for vpc in "${SITE_B_VPCS[@]}"; do
  cleanup_vpc "$vpc" "us-west-2"
done

# Clean up IAM roles
echo ""
echo "=== Cleaning up IAM roles ==="

for site in site-a site-b; do
  echo "  → Processing $site roles..."
  IAM_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, \`mq-ha-$site\`)].RoleName" --output text)
  
  for role in $IAM_ROLES; do
    echo "    Deleting role: $role"
    
    # Detach managed policies
    POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[*].PolicyArn' --output text)
    for policy in $POLICIES; do
      aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
    done
    
    # Delete inline policies
    INLINE=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[*]' --output text)
    for policy in $INLINE; do
      aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
    done
    
    # Delete role
    aws iam delete-role --role-name "$role" 2>/dev/null && echo "      ✅ Deleted" || echo "      ⚠️  Failed"
  done
done

# Clean up CloudWatch log groups
echo ""
echo "=== Cleaning up CloudWatch log groups ==="
aws logs delete-log-group --region us-east-1 --log-group-name "/aws/eks/mq-ha-site-a/cluster" 2>/dev/null && echo "  ✅ Deleted site-a log group" || echo "  ℹ️  No site-a log group"
aws logs delete-log-group --region us-west-2 --log-group-name "/aws/eks/mq-ha-site-b/cluster" 2>/dev/null && echo "  ✅ Deleted site-b log group" || echo "  ℹ️  No site-b log group"

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Verify cleanup:"
echo "  aws ec2 describe-vpcs --region us-east-1 --filters \"Name=tag:Project,Values=MQ-HA-Dual-Site\" --query 'Vpcs[*].VpcId'"
echo "  aws ec2 describe-vpcs --region us-west-2 --filters \"Name=tag:Project,Values=MQ-HA-Dual-Site\" --query 'Vpcs[*].VpcId'"
