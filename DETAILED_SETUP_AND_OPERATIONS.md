# Detailed Setup and Operations Guide

This guide provides a full, command-based runbook for this project.

## 1) Local Prerequisites

```bash
terraform -version
aws --version
kubectl version --client
```

## 2) Configure AWS Credentials Locally

```bash
aws configure
aws sts get-caller-identity
```

## 3) Configure GitHub OIDC Role for Actions

Run:

```bash
./setup-aws-github-oidc.sh
```

Expected output includes a role ARN like:

```text
arn:aws:iam::<ACCOUNT_ID>:role/GitHubActionsEKSRole
```

Add this in GitHub repository secrets:

- `AWS_ROLE_TO_ASSUME` = role ARN

## 4) Create Terraform Backend (S3 + DynamoDB)

Run:

```bash
./scripts/setup-terraform-backend.sh mqha-eks-tfstate-831488932214 mqha-eks-tflock us-east-1
```

Add GitHub repository variables:

- `TF_STATE_BUCKET=mqha-eks-tfstate-831488932214`
- `TF_STATE_REGION=us-east-1`
- `TF_LOCK_TABLE=mqha-eks-tflock`

## 5) Ensure IAM Role Has Required Extra Permissions

If missing, apply these inline policies:

### 5.1 DynamoDB lock permissions

```bash
aws iam put-role-policy --role-name GitHubActionsEKSRole --policy-name TerraformStateLockDynamoDB --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dynamodb:DescribeTable","dynamodb:GetItem","dynamodb:PutItem","dynamodb:DeleteItem","dynamodb:UpdateItem"],"Resource":"arn:aws:dynamodb:us-east-1:831488932214:table/mqha-eks-tflock"}]}'
```

### 5.2 S3 backend permissions

```bash
aws iam put-role-policy --role-name GitHubActionsEKSRole --policy-name TerraformStateBucketS3 --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:ListBucket"],"Resource":"arn:aws:s3:::mqha-eks-tfstate-831488932214"},{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject"],"Resource":"arn:aws:s3:::mqha-eks-tfstate-831488932214/*"}]}'
```

### 5.3 EKS permissions (if CreateCluster denied)

```bash
aws iam put-role-policy --role-name GitHubActionsEKSRole --policy-name EKSFullAccess --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["eks:*"],"Resource":"*"}]}'
```

## 6) Configure GitHub Environments

Create these environments in repository settings:

- `site-a-approval`
- `site-b-approval`
- `site-a-destroy-approval`
- `site-b-destroy-approval`

Set required reviewers for manual approval gates.

## 7) Run Deployment from GitHub Actions

Go to Actions → MQHA EKS CI/CD → Run workflow.

Action choices:

- `deploy-site-a`
- `deploy-site-b`
- `deploy-both`

What should happen:

1. `ci` passes
2. plan step runs with remote backend
3. environment approval requested
4. apply runs
5. MQ manifests applied

## 8) Validate Deployment

### 8.1 Verify cluster is reachable

```bash
aws eks update-kubeconfig --name mq-ha-site-a --region us-east-1
kubectl get nodes
kubectl get pods -n ibm-mq
kubectl get svc -n ibm-mq
```

### 8.2 Check site-b

```bash
aws eks update-kubeconfig --name mq-ha-site-b --region us-west-2
kubectl get nodes
kubectl get pods -n ibm-mq
kubectl get svc -n ibm-mq
```

## 9) Destroy via GitHub Actions

Run workflow with:

- `destroy-site-a`
- `destroy-site-b`
- `destroy-both`

Destroy jobs in workflow:

- show resources to be destroyed (`terraform plan -destroy`)
- run `terraform destroy`
- verify state remaining resources
- rerun destroy if needed

## 10) If Deploy Fails with "Already Exists"

This means resource exists in AWS but not in Terraform state.

Use import script:

```bash
./import-aws-resources.sh site-a us-east-1
./import-aws-resources.sh site-b us-west-2
```

Then rerun deployment.

## 11) If Orphaned IAM Node Roles Block Re-Deploy

```bash
for role in mq-ha-site-a-node-role mq-ha-site-b-node-role; do
  aws iam detach-role-policy --role-name $role --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy 2>/dev/null || true
  aws iam detach-role-policy --role-name $role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>/dev/null || true
  aws iam detach-role-policy --role-name $role --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy 2>/dev/null || true
  aws iam delete-role --role-name $role 2>/dev/null || true
done
```

## 12) Local Terraform Commands (with backend)

### site-a

```bash
cd terraform/sites/site-a
terraform init \
  -backend-config="bucket=mqha-eks-tfstate-831488932214" \
  -backend-config="key=mqha-eks/site-a/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=mqha-eks-tflock" \
  -backend-config="encrypt=true"
terraform plan
terraform apply -auto-approve
```

### site-b

```bash
cd ../site-b
terraform init \
  -backend-config="bucket=mqha-eks-tfstate-831488932214" \
  -backend-config="key=mqha-eks/site-b/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=mqha-eks-tflock" \
  -backend-config="encrypt=true"
terraform plan
terraform apply -auto-approve
```

## 13) Recommended Post-Test Cleanup

```bash
# Use workflow destroy-both (preferred)
# or local:
cd terraform/sites/site-a && terraform destroy -auto-approve
cd ../site-b && terraform destroy -auto-approve
```

Then validate no leftovers:

```bash
aws eks list-clusters --region us-east-1
aws eks list-clusters --region us-west-2
```

## 14) Helpful References in this Repo

- [README.md](README.md)
- [AWS_GITHUB_SETUP.md](AWS_GITHUB_SETUP.md)
- [RESOURCE_IMPORT_GUIDE.md](RESOURCE_IMPORT_GUIDE.md)
- [CHECK_RESOURCES_BEFORE_DESTROY.md](CHECK_RESOURCES_BEFORE_DESTROY.md)
- [scripts/setup-terraform-backend.sh](scripts/setup-terraform-backend.sh)
- [import-aws-resources.sh](import-aws-resources.sh)
