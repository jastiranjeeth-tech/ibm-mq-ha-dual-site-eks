# AWS GitHub OIDC Setup Guide

## Step 1: Create IAM OIDC Identity Provider in AWS

1. Go to AWS Console → IAM → Identity providers
2. Click "Add provider"
3. Select provider type: **OpenID Connect**
4. Provider URL: `https://token.actions.githubusercontent.com`
5. Audience: `sts.amazonaws.com`
6. Click "Add provider"

## Step 2: Create IAM Role for GitHub Actions

Create a new file `github-oidc-role.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
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
```

**Replace `YOUR_AWS_ACCOUNT_ID` with your actual AWS account ID**

Create the role:
```bash
aws iam create-role \
  --role-name GitHubActionsEKSRole \
  --assume-role-policy-document file://github-oidc-role.json
```

## Step 3: Attach Policies to the Role

Attach necessary policies for EKS, EC2, VPC, and Route53:

```bash
# EKS Full Access
aws iam attach-role-policy \
  --role-name GitHubActionsEKSRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# EC2 Full Access (for VPC, subnets, NAT gateways)
aws iam attach-role-policy \
  --role-name GitHubActionsEKSRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

# Route53 Full Access
aws iam attach-role-policy \
  --role-name GitHubActionsEKSRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess

# IAM Limited Access (for EKS IRSA)
aws iam attach-role-policy \
  --role-name GitHubActionsEKSRole \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
```

**OR** create a custom policy with minimum required permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:*",
        "ec2:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "iam:*",
        "route53:*",
        "kms:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Step 4: Add AWS Role ARN to GitHub Secrets

1. Go to your GitHub repository: https://github.com/jastiranjeeth-tech/ibm-mq-ha-dual-site-eks
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `AWS_ROLE_TO_ASSUME`
5. Value: `arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/GitHubActionsEKSRole`
6. Click **Add secret**

## Step 5: Create GitHub Environments for Approvals

1. Go to **Settings** → **Environments**
2. Create the following environments:
   - `site-a-approval`
   - `site-b-approval`
   - `site-a-destroy-approval`
   - `site-b-destroy-approval`

3. For each environment:
   - Click on the environment name
   - Check **Required reviewers**
   - Add yourself as a reviewer
   - Click **Save protection rules**

## Step 6: Get Your AWS Account ID

```bash
aws sts get-caller-identity --query Account --output text
```

## Quick Setup Script

Save this as `setup-aws-github-oidc.sh`:

```bash
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

# Attach policies
echo "Attaching policies..."
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
```

Make it executable and run:
```bash
chmod +x setup-aws-github-oidc.sh
./setup-aws-github-oidc.sh
```

## Verification

After setup, the workflow should be able to authenticate. The role ARN will be in format:
```
arn:aws:iam::123456789012:role/GitHubActionsEKSRole
```
