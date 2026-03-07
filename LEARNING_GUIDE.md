# IBM MQ Dual-Site Learning Guide

Hands-on guide for running IBM MQ across two EKS sites with DNS-based failover.

## Lab 1: Understand the Design

### Target state

- Site A: `QMHA_A` on 3-pod Native HA
- Site B: `QMHA_B` on 3-pod Native HA
- Route53 failover endpoint: clients use one hostname

### Key concept

Native HA gives high availability **within a cluster**.
Site-level disaster recovery is handled by **Route53 failover + client reconnect**.

## Lab 2: Deploy Site A EKS

```bash
cd terraform/sites/site-a
terraform init
terraform apply -auto-approve
```

Configure kube context:

```bash
aws eks update-kubeconfig --name mq-ha-site-a --region us-east-1
```

## Lab 3: Deploy Site B EKS

```bash
cd ../site-b
terraform init
terraform apply -auto-approve
```

Configure kube context:

```bash
aws eks update-kubeconfig --name mq-ha-site-b --region us-west-2
```

## Lab 4: Deploy MQ to both sites

```bash
cd ../../../scripts
./deploy-dual-site.sh <site-a-context> <site-b-context>
```

Validate both sites:

```bash
./check-dual-site-health.sh <site-a-context> <site-b-context>
```

Expected result:

- Site A has 3 running pods in `ibm-mq`
- Site B has 3 running pods in `ibm-mq`
- Each site has its own NLB service

## Lab 5: Build failover endpoint

Get site NLB hostnames:

```bash
./get-site-endpoints.sh <site-a-context> <site-b-context>
```

Create Route53 primary/secondary failover records:

```bash
./create-route53-failover-records.sh <hosted-zone-id> <record-name> <site-a-nlb-dns> <site-b-nlb-dns>
```

## Lab 6: Connect with MQ Explorer

Use Route53 record as host.

- Host: `<record-name>`
- Port: `1414`
- Channel: `DEV.APP.SVRCONN`
- User/Password: `app` / `passw0rd` (learning only)

Queue manager name can differ by site (`QMHA_A` vs `QMHA_B`).

## Lab 7: Simulate site failure

1. Verify traffic works to Site A.
2. Stop Site A MQ service or make Site A unhealthy.
3. Wait for Route53 health check to fail (typically ~1–2 minutes).
4. Reconnect and confirm client reaches Site B.

## Troubleshooting

### MQRC 2538 (HOST_NOT_AVAILABLE)

Check in order:

1. `kubectl get pods -n ibm-mq`
2. `kubectl get svc -n ibm-mq mq-ha-service`
3. `kubectl get endpoints -n ibm-mq mq-ha-service`
4. Security group rules allow `1414` from client CIDR
5. DNS now resolves to healthy site

### Route53 not failing over

- Ensure health check is TCP `1414`
- Ensure primary record has health check attached
- Ensure secondary record exists with same name/type and failover policy

## Production hardening checklist

- Replace default passwords
- Enable TLS for channels and console
- Enable CHLAUTH and CONNAUTH properly
- Restrict CIDRs in Terraform tfvars
- Add observability and alerting

---
This lab implements dual-site endpoint failover. Add message/data replication strategy separately for strict DR objectives.
