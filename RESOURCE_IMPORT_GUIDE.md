# Resource Import Guide

## When to Use Import

If AWS resources exist but Terraform doesn't know about them (state file mismatch), use the import script to bring them under Terraform management.

## Scenarios Requiring Import

1. **Partial Destroy Failure** - Some resources deleted, others remain
2. **Orphaned Resources** - Resources created manually or by another process
3. **State File Loss** - Terraform state was deleted but AWS resources still exist
4. **Migration** - Bringing existing AWS resources under Terraform control

## Quick Import

### Import All Resources for a Site

```bash
# Import all resources for site-a in us-east-1
./import-aws-resources.sh site-a us-east-1

# Import all resources for site-b in us-west-2
./import-aws-resources.sh site-b us-west-2
```

### Import Individual Resources

```bash
# Go to the site directory
cd terraform/sites/site-a
terraform init

# Import EKS cluster
terraform import 'module.eks.aws_eks_cluster.this[0]' mq-ha-site-a

# Import VPC
terraform import 'module.vpc.aws_vpc.this[0]' vpc-xxxxx

# Import node IAM role
terraform import 'module.eks.module.eks_managed_node_group["mq_nodes"].aws_iam_role.this[0]' mq-ha-site-a-node-role

# Import security group
terraform import 'module.eks.aws_security_group.node[0]' sg-xxxxx
```

## How Import Works

1. **Discovers** existing AWS resources by ID
2. **Queries** AWS for resource details
3. **Adds** resource to Terraform state file
4. **Links** resource to Terraform code configuration

**Example:**
```bash
terraform import 'module.eks.aws_eks_cluster.this[0]' mq-ha-site-a
# This tells Terraform: "The AWS EKS cluster named 'mq-ha-site-a' 
# should be managed by the code at module.eks.aws_eks_cluster.this[0]"
```

## Verification After Import

```bash
# Check what's in state
terraform state list

# View details of imported resource
terraform state show 'module.eks.aws_eks_cluster.this[0]'

# Run plan to see if anything needs changing
terraform plan
```

## Common Issues

### Issue: "Resource already exists in state"
```
Error: resource already exists in state
```
**Solution:** The resource is already in Terraform state. Run `terraform plan` to verify.

### Issue: "Resource not found in AWS"
```
Error: aws_eks_cluster.this: no matching AWS resource found
```
**Solution:** The resource doesn't exist in AWS, or you used the wrong ID/name.

### Issue: "Multiple resources match"
**Solution:** Use the full resource ID. For example:
```bash
terraform import 'module.vpc.aws_subnet.private[0]' subnet-xxxxx
```

## Workflow: Detect Orphaned Resources → Import or Delete

### Option 1: Import Existing Resources
```bash
# If resources should be kept
./import-aws-resources.sh site-a us-east-1

# Then verify
terraform -chdir=terraform/sites/site-a plan
terraform -chdir=terraform/sites/site-a apply
```

### Option 2: Delete Orphaned Resources
```bash
# If resources should be deleted
aws eks delete-cluster --name mq-ha-site-a --region us-east-1
aws ec2 delete-nat-gateway --nat-gateway-id ngw-xxxxx --region us-east-1
aws iam delete-role --role-name mq-ha-site-a-node-role
```

## After Successful Import

Once resources are imported and verified:

1. **Run terraform plan**
   ```bash
   terraform -chdir=terraform/sites/site-a plan
   ```
   Should show: "No changes. Your infrastructure matches the configuration."

2. **Deploy updates** (if needed)
   ```bash
   terraform -chdir=terraform/sites/site-a apply
   ```

3. **Destroy works properly** next time
   ```bash
   terraform -chdir=terraform/sites/site-a destroy
   ```
   All resources will be tracked and properly deleted

## GitHub Actions Workflow

If you encounter orphaned resources during a GitHub Actions deployment:

1. Use the GitHub environment to run terraform commands
2. OR manually import resources locally, then push state
3. OR delete orphaned resources manually, then retry deployment

To add import capability to the workflow, create a new job:

```yaml
cd_import_resources:
  if: github.event_name == 'workflow_dispatch' && inputs.action == 'import-site-a'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: aws-actions/configure-aws-credentials@v4
    - run: |
        chmod +x import-aws-resources.sh
        ./import-aws-resources.sh site-a us-east-1
```
