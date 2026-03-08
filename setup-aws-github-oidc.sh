#!/bin/bash

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

# Create trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:jastiranjeeth-tech/ibm-mq-ha-dual-site-eks:*"
        }
      }
    }
  ]
}
EOF

# Check if OIDC provider exists
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com" 2>/dev/null; then
  echo "Creating OIDC provider..."
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
else
  echo "OIDC provider already exists"
fi

# Create role
echo "Creating IAM role..."
aws iam create-role \
  --role-name GitHubActionsEKSRole \
  --assume-role-policy-document file://trust-policy.json \
  || echo "Role might already exist"

# Create additional policy for self-role access
cat > additional-permissions.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:GetRole",
        "iam:ListAttachedRolePolicies",
        "iam:GetRolePolicy",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
EOF

echo "Creating IAM permissions policy..."
aws iam put-role-policy \
  --role-name GitHubActionsEKSRole \
  --policy-name EKSAdditionalPermissions \
  --policy-document file://additional-permissions.json

echo "Creating KMS and Logs permissions policy..."
aws iam put-role-policy \
  --role-name GitHubActionsEKSRole \
  --policy-name KMSandLogsPermissions \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["kms:*","logs:*"],"Resource":"*"}]}'

# Attach policies
echo "Attaching managed policies..."
aws iam attach-role-policy --role-name GitHubActionsEKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam attach-role-policy --role-name GitHubActionsEKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-role-policy --role-name GitHubActionsEKSRole --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess
aws iam attach-role-policy --role-name GitHubActionsEKSRole --policy-arn arn:aws:iam::aws:policy/IAMFullAccess

# Output the role ARN
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/GitHubActionsEKSRole"
echo ""
echo "✅ Setup complete!"
echo ""
echo "Add this to GitHub Secrets as AWS_ROLE_TO_ASSUME:"
echo "$ROLE_ARN"
echo ""
echo "Go to: https://github.com/jastiranjeeth-tech/ibm-mq-ha-dual-site-eks/settings/secrets/actions"
