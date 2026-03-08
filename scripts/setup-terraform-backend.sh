#!/usr/bin/env bash
set -euo pipefail

# Creates Terraform remote backend resources (S3 + DynamoDB)
# Usage:
#   ./scripts/setup-terraform-backend.sh <bucket-name> <dynamodb-table> [region]
# Example:
#   ./scripts/setup-terraform-backend.sh mqha-eks-tfstate-831488932214 mqha-eks-tflock us-east-1

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <bucket-name> <dynamodb-table> [region]"
  exit 1
fi

BUCKET_NAME="$1"
LOCK_TABLE="$2"
REGION="${3:-us-east-1}"

echo "Region: $REGION"
echo "S3 bucket: $BUCKET_NAME"
echo "DynamoDB table: $LOCK_TABLE"

echo "==> Checking AWS identity"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "==> S3 bucket already exists: $BUCKET_NAME"
else
  echo "==> Creating S3 bucket: $BUCKET_NAME"
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
fi

echo "==> Enabling bucket versioning"
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo "==> Enabling bucket encryption"
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "==> Blocking public access"
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$REGION" >/dev/null 2>&1; then
  echo "==> DynamoDB table already exists: $LOCK_TABLE"
else
  echo "==> Creating DynamoDB lock table: $LOCK_TABLE"
  aws dynamodb create-table \
    --table-name "$LOCK_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"

  echo "==> Waiting for DynamoDB table to become ACTIVE"
  aws dynamodb wait table-exists --table-name "$LOCK_TABLE" --region "$REGION"
fi

echo ""
echo "✅ Terraform backend resources are ready"
echo "Set these GitHub Repository Variables:"
echo "  TF_STATE_BUCKET=$BUCKET_NAME"
echo "  TF_STATE_REGION=$REGION"
echo "  TF_LOCK_TABLE=$LOCK_TABLE"
