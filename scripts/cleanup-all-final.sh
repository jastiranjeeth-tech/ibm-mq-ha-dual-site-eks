#!/bin/bash
set -e

echo "=== Comprehensive VPC cleanup for all orphaned resources ==="

# Function to cleanup VPC with proper security group handling
cleanup_vpc_complete() {
  local VPC_ID=$1
  local REGION=$2
  
  echo ""
  echo "🧹 Cleaning VPC: $VPC_ID in $REGION"
  
  # Get all non-default security groups
  echo "  → Getting security groups..."
  SGS=$(aws ec2 describe-security-groups --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
  
  if [ -n "$SGS" ]; then
    echo "  → Revoking all security group rules..."
    for sg in $SGS; do
      echo "    Processing $sg..."
      
      # Revoke all ingress rules by rule ID
      INGRESS_RULES=$(aws ec2 describe-security-group-rules --region $REGION \
        --filter "Name=group-id,Values=$sg" \
        --query 'SecurityGroupRules[?IsEgress==`false`].SecurityGroupRuleId' --output text)
      
      for rule in $INGRESS_RULES; do
        aws ec2 revoke-security-group-ingress --region $REGION \
          --group-id $sg --security-group-rule-ids $rule 2>/dev/null || true
      done
      
      # Revoke all egress rules by rule ID
      EGRESS_RULES=$(aws ec2 describe-security-group-rules --region $REGION \
        --filter "Name=group-id,Values=$sg" \
        --query 'SecurityGroupRules[?IsEgress==`true`].SecurityGroupRuleId' --output text)
      
      for rule in $EGRESS_RULES; do
        aws ec2 revoke-security-group-egress --region $REGION \
          --group-id $sg --security-group-rule-ids $rule 2>/dev/null || true
      done
    done
    
    echo "  → Deleting security groups..."
    for sg in $SGS; do
      echo "    Deleting $sg..."
      aws ec2 delete-security-group --region $REGION --group-id $sg 2>/dev/null || true
    done
  fi
  
  # Delete VPC
  echo "  → Deleting VPC: $VPC_ID"
  aws ec2 delete-vpc --region $REGION --vpc-id $VPC_ID && \
    echo "  ✅ VPC $VPC_ID deleted" || \
    echo "  ⚠️  VPC deletion failed"
}

# Site-A VPCs in us-east-1
echo ""
echo "=== Cleaning Site-A VPCs (us-east-1) ==="
SITE_A_VPCS=("vpc-03fc8cd84d5fcd323" "vpc-036162bbc019c34cc" "vpc-0703381b693cc4696" "vpc-0bc239fb1d508570c")
for vpc in "${SITE_A_VPCS[@]}"; do
  cleanup_vpc_complete "$vpc" "us-east-1"
done

# Site-B VPCs in us-west-2
echo ""
echo "=== Cleaning Site-B VPCs (us-west-2) ==="
SITE_B_VPCS=("vpc-0937623017216bfe5" "vpc-054f0dba7e3c9a0e7" "vpc-06c18093eb7f1081b")
for vpc in "${SITE_B_VPCS[@]}"; do
  cleanup_vpc_complete "$vpc" "us-west-2"
done

# Clean up IAM roles
echo ""
echo "=== Cleaning IAM Roles ==="
for site in site-a site-b; do
  echo "  → Processing mq-ha-$site roles..."
  IAM_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, \`mq-ha-$site\`)].RoleName" --output text)
  
  for role in $IAM_ROLES; do
    echo "    Deleting $role..."
    
    # Detach managed policies
    MANAGED=$(aws iam list-attached-role-policies --role-name "$role" \
      --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || true)
    for policy in $MANAGED; do
      aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
    done
    
    # Delete inline policies
    INLINE=$(aws iam list-role-policies --role-name "$role" \
      --query 'PolicyNames[*]' --output text 2>/dev/null || true)
    for policy in $INLINE; do
      aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
    done
    
    # Delete role
    aws iam delete-role --role-name "$role" 2>/dev/null && \
      echo "      ✅ Deleted" || echo "      ⚠️  Failed"
  done
done

echo ""
echo "✅ All cleanup complete!"
echo ""
echo "Verify with:"
echo "  aws ec2 describe-vpcs --region us-east-1 --filters Name=tag:Project,Values=MQ-HA-Dual-Site"
echo "  aws ec2 describe-vpcs --region us-west-2 --filters Name=tag:Project,Values=MQ-HA-Dual-Site"
