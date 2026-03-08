# IBM MQ Dual-Site DR on AWS EKS

This repository deploys IBM MQ in a dual-site EKS design:

- Site A (primary): 3-pod MQ Native HA
- Site B (standby): 3-pod MQ Native HA
- Route53 failover DNS for client endpoint switch

> MQ Native HA provides high availability within a site/cluster. Cross-site failover in this project is handled at DNS/client routing level.

## Architecture

```text
Clients (MQ Explorer / Apps)
                        |
       mq.example.com (Route53 failover)
                        |
+-------+--------------------------+
|                                  |
PRIMARY (healthy)            SECONDARY (failover)
|                                  |
Site A NLB:1414/9443         Site B NLB:1414/9443
|                                  |
EKS site-a + MQ NHA(3)       EKS site-b + MQ NHA(3)
```

## Prerequisites

- AWS account with permissions for EKS, EC2, IAM, KMS, Route53, S3, DynamoDB, CloudWatch
- Terraform >= 1.6
- AWS CLI v2
- kubectl
- GitHub repository with Actions enabled

## One-Time Setup (Required)

### 1) Configure AWS OIDC role for GitHub Actions

Use the script and guide:

- [setup-aws-github-oidc.sh](setup-aws-github-oidc.sh)
- [AWS_GITHUB_SETUP.md](AWS_GITHUB_SETUP.md)

Add repository secret:

- `AWS_ROLE_TO_ASSUME` = IAM role ARN used by GitHub Actions

### 2) Create Terraform remote backend (S3 + DynamoDB)

```bash
./scripts/setup-terraform-backend.sh mqha-eks-tfstate-831488932214 mqha-eks-tflock us-east-1
```

Add GitHub repository variables:

- `TF_STATE_BUCKET` = `mqha-eks-tfstate-831488932214`
- `TF_STATE_REGION` = `us-east-1`
- `TF_LOCK_TABLE` = `mqha-eks-tflock`

### 3) Create GitHub Environments (manual approvals)

- `site-a-approval`
- `site-b-approval`
- `site-a-destroy-approval`
- `site-b-destroy-approval`

Set required reviewers on each environment.

## CI/CD Workflow

Workflow file: [​.github/workflows/mqha-eks-ci-cd.yml](.github/workflows/mqha-eks-ci-cd.yml)

### CI (push / PR)

- Terraform fmt + validate
- YAML lint
- shellcheck
- terraform plan matrix (site-a, site-b)

### Manual actions (workflow_dispatch)

Action options:

- `deploy-site-a`
- `deploy-site-b`
- `deploy-both`
- `destroy-site-a`
- `destroy-site-b`
- `destroy-both`

## Local Deployment (Optional)

### Deploy site-a

```bash
cd terraform/sites/site-a
terraform init \
      -backend-config="bucket=mqha-eks-tfstate-831488932214" \
      -backend-config="key=mqha-eks/site-a/terraform.tfstate" \
      -backend-config="region=us-east-1" \
      -backend-config="dynamodb_table=mqha-eks-tflock" \
      -backend-config="encrypt=true"
terraform apply -auto-approve
```

### Deploy site-b

```bash
cd ../site-b
terraform init \
      -backend-config="bucket=mqha-eks-tfstate-831488932214" \
      -backend-config="key=mqha-eks/site-b/terraform.tfstate" \
      -backend-config="region=us-east-1" \
      -backend-config="dynamodb_table=mqha-eks-tflock" \
      -backend-config="encrypt=true"
terraform apply -auto-approve
```

### Deploy MQ manifests

```bash
cd ../../../scripts
./deploy-site-mq-ha.sh site-a
./deploy-site-mq-ha.sh site-b
```

## Troubleshooting Aids

- Resource import: [import-aws-resources.sh](import-aws-resources.sh)
- Import guide: [RESOURCE_IMPORT_GUIDE.md](RESOURCE_IMPORT_GUIDE.md)
- Pre-destroy verification: [CHECK_RESOURCES_BEFORE_DESTROY.md](CHECK_RESOURCES_BEFORE_DESTROY.md)
- Cleanup helper: [cleanup-aws-resources.sh](cleanup-aws-resources.sh)

## Detailed Step-by-Step Operations Guide

See [DETAILED_SETUP_AND_OPERATIONS.md](DETAILED_SETUP_AND_OPERATIONS.md) for complete end-to-end setup, deploy, validation, failover testing, destroy, and recovery commands.
