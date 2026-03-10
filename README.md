# IBM MQ Dual-Site DR on AWS EKS

This repository deploys IBM MQ in a dual-site disaster recovery configuration on AWS EKS:

- **Site A (us-east-1)**: 3-pod MQ Native HA queue manager group
- **Site B (us-west-2)**: 3-pod MQ Native HA queue manager group (independent from Site A)
- **Inter-site DR**: MQ sender/receiver channels for cross-datacenter replication
- **Client failover**: Route53 DNS-based failover between sites

## What is MQ Native HA?

IBM MQ **Native HA** (introduced in MQ 9.2+) is a Kubernetes-aware high availability mode where:

- 3 queue manager instances form a replicated group
- 1 instance runs as **active** (STATUS=Running)
- 2 instances run as **standby replicas** (STATUS=Replica)
- Automatic failover within the cluster if active instance fails
- Uses Kubernetes StatefulSet with persistent volumes

**Key difference from Multi-Instance mode:**
- **Native HA**: No shared storage, uses log/data replication between pods
- **Multi-Instance**: Requires shared NFS/EFS storage (not used in this setup)

## Architecture

```text
Clients (MQ Explorer / Apps)
                        |
       mq.example.com (Route53 failover DNS)
                        |
+-------+--------------------------+
|                                  |
PRIMARY (healthy)            SECONDARY (failover)
|                                  |
Site A NLB:1414/9443         Site B NLB:1414/9443
|                                  |
EKS us-east-1                EKS us-west-2
|                                  |
QMHA_A (Native HA)           QMHA_B (Native HA)
├─ mq-ha-0 (Replica)         ├─ mq-ha-0 (Replica)
├─ mq-ha-1 (Replica)         ├─ mq-ha-1 (Replica)
└─ mq-ha-2 (Running)         └─ mq-ha-2 (Running)
        |                            |
        +-------- MQ Channels -------+
             (SITE.A.TO.B / SITE.B.TO.A)
```

### Pod Readiness Behavior

Standard MQ Native HA behavior (as deployed):

- **1/3 pods** show `1/1 Ready` (active queue manager)
- **2/3 pods** show `0/1 Running` (standby replicas)
- Only the active QM pod passes `chkmqready` readiness probe

This matches traditional IBM MQ Native HA expectations.

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

Workflow file: [.github/workflows/mqha-eks-ci-cd.yml](.github/workflows/mqha-eks-ci-cd.yml)

### CI (push / PR)

- Terraform fmt + validate
- YAML lint
- shellcheck
- terraform plan matrix (site-a, site-b)

### Manual deployment actions (workflow_dispatch)

Independent deployment options:

- `deploy-terraform-site-a` - Deploy site-a infrastructure only (EKS, VPC, etc)
- `deploy-terraform-site-b` - Deploy site-b infrastructure only
- `deploy-k8s-site-a` - Deploy site-a MQ manifests only
- `deploy-k8s-site-b` - Deploy site-b MQ manifests only
- `deploy-site-a` - Full site-a deployment (terraform + k8s)
- `deploy-site-b` - Full site-b deployment (terraform + k8s)
- `deploy-both` - Deploy both sites end-to-end
- `destroy-site-a` - Destroy site-a with approval
- `destroy-site-b` - Destroy site-b with approval
- `destroy-both` - Destroy both sites with approval

### Deployment Process

When running pipeline deployment:

1. **Terraform phase** creates:
   - EKS cluster with managed node groups
   - VPC with private/public subnets
   - EBS CSI driver addon (v1.53.0-eksbuild.1)
   - IAM roles for IRSA
   - Security groups

2. **Kubernetes phase** deploys:
   - Namespace: `ibm-mq`
   - StorageClass: `mq-storage` (gp3 encrypted)
   - ConfigMap: MQ configuration (qm.ini, mqsc.ini)
   - Secret: MQ admin/app passwords
   - StatefulSet: 3 replicas with persistent volumes
   - Services: LoadBalancer (NLB) + Headless

3. **Verification steps**:
   ```bash
   # Switch to site context
   aws eks update-kubeconfig --region us-east-1 --name mq-ha-site-a
   
   # Check pod status (expect 1/3 Ready, 2/3 NotReady)
   kubectl -n ibm-mq get pods
   
   # Verify queue manager roles
   for p in mq-ha-0 mq-ha-1 mq-ha-2; do
     kubectl -n ibm-mq exec $p -- dspmq
   done
   # Expected: 1 Running, 2 Replica
   
   # Get LoadBalancer endpoint
   kubectl -n ibm-mq get svc mq-ha-service
   ```

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

## MQ Configuration Details

### Native HA Configuration (qm.ini)

Each queue manager is configured with 3 Native HA instances in [k8s/site-a/mq-configmap.yaml](k8s/site-a/mq-configmap.yaml):

```ini
NativeHAInstance:
  Name=mq-ha-0
  ReplicationAddress=mq-ha-0.mq-ha-headless.ibm-mq.svc.cluster.local(1414)
NativeHAInstance:
  Name=mq-ha-1
  ReplicationAddress=mq-ha-1.mq-ha-headless.ibm-mq.svc.cluster.local(1414)
NativeHAInstance:
  Name=mq-ha-2
  ReplicationAddress=mq-ha-2.mq-ha-headless.ibm-mq.svc.cluster.local(1414)
```

**Key points:**
- Uses Kubernetes headless service DNS for pod-to-pod replication
- `publishNotReadyAddresses: true` on headless service ensures standby replicas can resolve DNS
- StatefulSet `podManagementPolicy: Parallel` allows all 3 pods to start simultaneously

### Inter-Site Channels (mqsc.ini)

**Site A to Site B:**
```mqsc
DEFINE CHANNEL(SITE.A.TO.B) CHLTYPE(SDR) CONNAME('site-b-nlb-endpoint:1414') REPLACE
DEFINE CHANNEL(SITE.B.TO.A) CHLTYPE(RCVR) REPLACE
```

**Site B to Site A:**
```mqsc
DEFINE CHANNEL(SITE.B.TO.A) CHLTYPE(SDR) CONNAME('site-a-nlb-endpoint:1414') REPLACE
DEFINE CHANNEL(SITE.A.TO.B) CHLTYPE(RCVR) REPLACE
```

Channels enable:
- Message replication between sites
- Queue synchronization
- DR failover capability

### StatefulSet Configuration

Key settings in [k8s/site-a/mq-statefulset.yaml](k8s/site-a/mq-statefulset.yaml):

```yaml
spec:
  replicas: 3
  podManagementPolicy: Parallel
  serviceName: mq-ha-headless
  template:
    spec:
      initContainers:
      - name: volume-permissions
        image: busybox:latest
        command: ['sh', '-c', 'chown -R 1001:root /mnt/mqm /mnt/mqm-log']
      containers:
      - name: mq
        image: icr.io/ibm-messaging/mq:latest
        env:
        - name: MQ_NATIVE_HA
          value: "true"
        volumeMounts:
        - name: data
          mountPath: /mnt/mqm
        - name: log
          mountPath: /mnt/mqm-log
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: mq-storage
      resources:
        requests:
          storage: 10Gi
  - metadata:
      name: log
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: mq-storage
      resources:
        requests:
          storage: 10Gi
```

## Testing Native HA Failover

### Within Site (Automatic)

Delete the active queue manager pod:

```bash
# Identify active pod
kubectl -n ibm-mq get pods
for p in mq-ha-0 mq-ha-1 mq-ha-2; do
  kubectl -n ibm-mq exec $p -- dspmq
done

# Delete active pod (e.g., mq-ha-2)
kubectl -n ibm-mq delete pod mq-ha-2

# Wait 30-60 seconds for failover
sleep 45

# Verify new active
kubectl -n ibm-mq get pods
for p in mq-ha-0 mq-ha-1 mq-ha-2; do
  kubectl -n ibm-mq exec $p -- dspmq
done
```

Expected behavior:
- Another replica promotes to Running (active)
- Deleted pod recreates and becomes Replica
- Final state: 1 Running, 2 Replica

### Cross-Site (Manual DNS Failover)

Update Route53 record to point to Site B NLB endpoint when Site A fails health checks.

## Verification Commands

### Check Native HA Status

```bash
# Site A
aws eks update-kubeconfig --region us-east-1 --name mq-ha-site-a
kubectl -n ibm-mq get pods -o wide
for p in mq-ha-0 mq-ha-1 mq-ha-2; do
  echo "=== $p ==="
  kubectl -n ibm-mq exec $p -- dspmq
done

# Site B
aws eks update-kubeconfig --region us-west-2 --name mq-ha-site-b
kubectl -n ibm-mq get pods -o wide
for p in mq-ha-0 mq-ha-1 mq-ha-2; do
  echo "=== $p ==="
  kubectl -n ibm-mq exec $p -- dspmq
done
```

### Test MQ Connection

```bash
# Get NLB endpoint
NLB=$(kubectl -n ibm-mq get svc mq-ha-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test with MQ sample client
echo "DEFINE QLOCAL(TEST.QUEUE) REPLACE" | runmqsc -c -u admin -w 60 $NLB
```

### Check Inter-Site Channels

```bash
# On Site A active pod
kubectl -n ibm-mq exec mq-ha-2 -- bash -c "echo 'DISPLAY CHSTATUS(SITE.A.TO.B)' | runmqsc QMHA_A"

# On Site B active pod
kubectl -n ibm-mq exec mq-ha-1 -- bash -c "echo 'DISPLAY CHSTATUS(SITE.B.TO.A)' | runmqsc QMHA_B"
```

Expected: `STATUS(RUNNING)` or `STATUS(RETRYING)` if endpoint not reachable.

## Troubleshooting Aids

- Resource import: [import-aws-resources.sh](import-aws-resources.sh)
- Import guide: [RESOURCE_IMPORT_GUIDE.md](RESOURCE_IMPORT_GUIDE.md)
- Pre-destroy verification: [CHECK_RESOURCES_BEFORE_DESTROY.md](CHECK_RESOURCES_BEFORE_DESTROY.md)
- Cleanup helper: [cleanup-aws-resources.sh](cleanup-aws-resources.sh)

## Detailed Step-by-Step Operations Guide

See [DETAILED_SETUP_AND_OPERATIONS.md](DETAILED_SETUP_AND_OPERATIONS.md) for complete end-to-end setup, deploy, validation, failover testing, destroy, and recovery commands.
