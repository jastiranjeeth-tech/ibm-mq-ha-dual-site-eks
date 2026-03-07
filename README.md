# IBM MQ Dual-Site DR on AWS EKS

Two-site IBM MQ design on EKS:

- **Site A (Primary):** 3-pod MQ Native HA
- **Site B (Standby):** 3-pod MQ Native HA
- **Client endpoint:** Route53 failover DNS

> Note: MQ Native HA is intra-cluster. Cross-site failover is implemented at DNS/client-routing level.

## Architecture

```
                      Clients (MQ Explorer / Apps)
                                |
                       mq.example.com (Route53)
                                |
              +-----------------+-----------------+
              |                                   |
        PRIMARY (healthy)                   SECONDARY (used on failover)
              |                                   |
      Site A NLB:1414/9443                 Site B NLB:1414/9443
              |                                   |
      EKS Cluster Site A                    EKS Cluster Site B
      mq-ha (3 pods NHA)                    mq-ha (3 pods NHA)
```

## Project Structure

```
MQHA_EKS/
├── README.md
├── LEARNING_GUIDE.md
├── terraform/
│   ├── global-dns/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   └── sites/
│       ├── site-a/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   ├── versions.tf
│       │   └── terraform.tfvars
│       └── site-b/
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           ├── versions.tf
│           └── terraform.tfvars
├── k8s/
│   ├── site-a/
│   │   ├── namespace.yaml
│   │   ├── storage-class.yaml
│   │   ├── mq-configmap.yaml
│   │   ├── mq-secret.yaml
│   │   └── mq-statefulset.yaml
│   └── site-b/
│       ├── namespace.yaml
│       ├── storage-class.yaml
│       ├── mq-configmap.yaml
│       ├── mq-secret.yaml
│       └── mq-statefulset.yaml
└── scripts/
    ├── deploy-site-mq-ha.sh
    ├── deploy-dual-site.sh
    ├── get-site-endpoints.sh
    ├── check-dual-site-health.sh
    └── create-route53-failover-records.sh
```

## Quick Start

### 1) Deploy EKS Site A

```bash
cd terraform/sites/site-a
terraform init
terraform apply -auto-approve
```

### 2) Deploy EKS Site B

```bash
cd ../site-b
terraform init
terraform apply -auto-approve
```

### 3) Configure kube contexts

```bash
aws eks update-kubeconfig --name mq-ha-site-a --region us-east-1
aws eks update-kubeconfig --name mq-ha-site-b --region us-west-2
kubectl config get-contexts
```

### 4) Deploy MQ to both sites

```bash
cd ../../../scripts
./deploy-dual-site.sh <site-a-context> <site-b-context>
```

### 5) Get NLB endpoints

```bash
./get-site-endpoints.sh <site-a-context> <site-b-context>
```

### 6) Create Route53 failover record

```bash
./create-route53-failover-records.sh <hosted-zone-id> <record-name> <site-a-nlb-dns> <site-b-nlb-dns>
```

### 7) Connect from MQ Explorer

- Host: your Route53 record (example `mq.example.com`)
- Port: `1414`
- Channel: `DEV.APP.SVRCONN`
- Queue manager:
  - Site A uses `QMHA_A`
  - Site B uses `QMHA_B`

## What is Implemented

- Two independent EKS clusters (one per site)
- Two independent 3-pod MQ Native HA StatefulSets
- External NLB per site
- Route53 failover records for site failover

## Important DR Note

This setup gives **endpoint failover** between sites. Message/data replication across sites is not automatic from Native HA itself.

For strict cross-site RPO/RTO, add an MQ DR replication pattern at application or MQ topology level.

## Security Note

Current manifests are learning-focused:

- default passwords
- channel auth disabled
- wide CIDR opens in tfvars

Harden these before production use.

## CI/CD

GitHub Actions workflow is added at [.github/workflows/mqha-eks-ci-cd.yml](.github/workflows/mqha-eks-ci-cd.yml).

### CI checks on push/PR

- Terraform `fmt` + `validate`
- Kubernetes YAML lint
- Shell script lint

### Manual CD (workflow_dispatch)

You can manually deploy `site-a`, `site-b`, or `both` from Actions.

The workflow has separate deploy jobs:

- `cd_deploy_site_a` (environment: `site-a-approval`)
- `cd_deploy_site_b` (environment: `site-b-approval`)

Set required reviewers in GitHub Environments for approval gates.

Required GitHub secret:

- `AWS_ROLE_TO_ASSUME` (IAM role for OIDC federation from GitHub Actions)
