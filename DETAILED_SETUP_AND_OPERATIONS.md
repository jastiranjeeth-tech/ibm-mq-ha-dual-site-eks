# Detailed Setup and Operations Guide

This document explains:

1. What each Terraform step is doing
2. How MQ Native HA is deployed with kubectl
3. Full request path: Internet → AWS → MQ → backend consumers
4. Day-2 operations (deploy, verify, failover, destroy, recovery)

---

## 1) End-to-End Architecture (What You Built)

```text
Internet Client / MQ App
        |
        | DNS lookup (Route53 failover record)
        v
   mq.example.com
        |
        +--> Primary target (Site A NLB, if healthy)
        |         |
        |         +--> EKS Service type LoadBalancer (mq-ha-service)
        |                 |
        |                 +--> StatefulSet pods (mq-ha-0/1/2)
        |                         |
        |                         +--> Active queue manager instance
        |                         +--> EBS-backed storage for MQ data
        |
        +--> Secondary target (Site B NLB, when Site A health fails)
                  |
                  +--> EKS Service type LoadBalancer (mq-ha-service)
                          |
                          +--> StatefulSet pods (mq-ha-0/1/2)
                                  |
                                  +--> Active queue manager instance
```

### Ports in this project

- `1414`: MQ client channel traffic
- `9443`: MQ web console

### Important behavior

- MQ Native HA works within each site (within that EKS cluster)
- Cross-site switchover is DNS-driven via Route53 failover

---

## 2) Terraform Code Explained Step by Step

Each site folder has Terraform for one independent EKS environment.

### Step A: Terraform backend init

When `terraform init` runs with S3 + DynamoDB backend:

- Reads/writes state in S3 bucket
- Uses DynamoDB table for state lock (prevents concurrent write corruption)

Command pattern used:

```bash
terraform -chdir=terraform/sites/site-a init \
  -backend-config="bucket=mqha-eks-tfstate-831488932214" \
  -backend-config="key=mqha-eks/site-a/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=mqha-eks-tflock" \
  -backend-config="encrypt=true"
```

### Step B: VPC module creation

Terraform creates:

- VPC
- Public subnets
- Private subnets
- Internet Gateway
- NAT Gateway
- Route tables and associations

Why: worker nodes run in private subnets; NLB/public access handled via AWS networking.

### Step C: EKS module creation

Terraform creates:

- EKS control plane
- Cluster security groups
- EKS managed node group (`mq_nodes`)
- Node IAM role (`mq-ha-site-a-node-role` or site-b equivalent)
- CloudWatch log group for EKS control plane
- KMS key/alias for EKS encryption settings used by module

### Step D: EBS CSI IRSA + addon

Terraform creates:

- IAM role for service account (IRSA) for EBS CSI driver
- EKS addon `aws-ebs-csi-driver`

Why: StatefulSet PVCs need dynamic EBS volume provisioning.

### Step E: Plan and Apply lifecycle

- `terraform plan`: compares desired HCL vs current state + AWS reality
- `terraform apply`: executes create/update/delete actions in dependency order

---

## 3) Kubernetes / MQ Native HA Deployment Explained

Deployment script applies manifests in strict order:

```bash
./scripts/deploy-site-mq-ha.sh site-a
```

Sequence:

1. Namespace (`ibm-mq`)
2. StorageClass (`mq-storage`, EBS gp3, encrypted)
3. ConfigMap (MQSC definitions)
4. Secret (admin/app passwords)
5. Service + headless service + StatefulSet

### Why this order matters

- StatefulSet needs namespace and storage class first
- Pod startup depends on mounted config and secret
- LoadBalancer service creates NLB after selectors match running pods

### StatefulSet behavior in this setup

- `replicas: 3` gives three MQ pods
- Pod anti-affinity spreads pods across nodes
- Each pod gets its own EBS volume via `volumeClaimTemplates`
- Liveness/readiness probes drive traffic eligibility

### Site differences

- Site A queue manager: `QMHA_A`
- Site B queue manager: `QMHA_B`

---

## 4) How an Internet Request Reaches MQ and Backend

1. Client resolves `mq.example.com` in Route53
2. Route53 health checks decide primary vs secondary site
3. DNS returns active site NLB hostname
4. Client opens TCP connection to NLB on `1414`
5. NLB forwards to EKS `mq-ha-service`
6. Kubernetes routes to ready MQ pod
7. MQ channel (for example `DEV.APP.SVRCONN`) authenticates user
8. App puts/gets message on queue manager
9. Backend consumer application (inside or outside cluster) reads messages from MQ queue

---

## 5) One-Time Platform Setup (Commands)

## 5.1 Verify local tools

```bash
terraform -version
aws --version
kubectl version --client
```

## 5.2 Configure local AWS CLI

```bash
aws configure
aws sts get-caller-identity
```

## 5.3 Create GitHub OIDC role

```bash
./setup-aws-github-oidc.sh
```

Add GitHub secret:

- `AWS_ROLE_TO_ASSUME`

## 5.4 Create Terraform backend resources

```bash
./scripts/setup-terraform-backend.sh mqha-eks-tfstate-831488932214 mqha-eks-tflock us-east-1
```

Add GitHub repository variables:

- `TF_STATE_BUCKET=mqha-eks-tfstate-831488932214`
- `TF_STATE_REGION=us-east-1`
- `TF_LOCK_TABLE=mqha-eks-tflock`

## 5.5 GitHub Environments for manual approval

Create:

- `site-a-approval`
- `site-b-approval`
- `site-a-destroy-approval`
- `site-b-destroy-approval`

---

## 6) Deploy Operations (GitHub Actions)

Workflow action options:

- `deploy-site-a`
- `deploy-site-b`
- `deploy-both`
- `destroy-site-a`
- `destroy-site-b`
- `destroy-both`

### Deploy flow in pipeline

1. CI validation
2. Remote backend init checks
3. Auto-import reconciliation (`import-aws-resources.sh`) for pre-existing AWS objects
4. Terraform plan
5. Manual approval gate
6. Terraform apply
7. `kubectl apply` for MQ manifests

---

## 7) Validation Commands After Deploy

### Site A

```bash
aws eks update-kubeconfig --name mq-ha-site-a --region us-east-1
kubectl get nodes
kubectl get pods -n ibm-mq -o wide
kubectl get svc -n ibm-mq
kubectl get pvc -n ibm-mq
```

### Site B

```bash
aws eks update-kubeconfig --name mq-ha-site-b --region us-west-2
kubectl get nodes
kubectl get pods -n ibm-mq -o wide
kubectl get svc -n ibm-mq
kubectl get pvc -n ibm-mq
```

---

## 8) Troubleshooting Common Failures

### AlreadyExists errors (KMS alias/log group/role)

Cause: object exists in AWS but not in Terraform state.

Fix:

```bash
./import-aws-resources.sh site-a us-east-1
./import-aws-resources.sh site-b us-west-2
```

### State lock errors

Cause: missing DynamoDB permissions or stale lock.

Fix:

- Verify IAM permissions for DynamoDB table
- Check lock table item and remove stale lock only if no active run

### Backend access errors

Cause: missing S3 permissions or missing repo variables.

Fix:

- Ensure `TF_STATE_BUCKET`, `TF_STATE_REGION`, `TF_LOCK_TABLE` exist
- Ensure role has S3 bucket/object permissions

---

## 9) Destroy and Cleanup

Use workflow `destroy-site-a`, `destroy-site-b`, or `destroy-both`.

Destroy jobs do:

1. Show what will be destroyed (`plan -destroy`)
2. Destroy resources
3. Verify Terraform state
4. Retry destroy if state still contains resources

Post-check:

```bash
aws eks list-clusters --region us-east-1
aws eks list-clusters --region us-west-2
```

---

## 10) Security and Production Notes

Current manifests are learning-oriented:

- default passwords in secret
- broad CIDR access possible in variables
- CHLAUTH disabled in MQ config for ease of testing

Before production:

- rotate credentials and use external secret manager
- restrict CIDRs
- enable proper MQ channel authentication/authorization
- add TLS certificates and hardened queue/channel policy

---

## 11) Related Documents

- [README.md](README.md)
- [AWS_GITHUB_SETUP.md](AWS_GITHUB_SETUP.md)
- [RESOURCE_IMPORT_GUIDE.md](RESOURCE_IMPORT_GUIDE.md)
- [CHECK_RESOURCES_BEFORE_DESTROY.md](CHECK_RESOURCES_BEFORE_DESTROY.md)
- [import-aws-resources.sh](import-aws-resources.sh)
- [scripts/setup-terraform-backend.sh](scripts/setup-terraform-backend.sh)
