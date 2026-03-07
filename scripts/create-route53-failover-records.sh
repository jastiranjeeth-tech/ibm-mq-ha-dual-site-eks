#!/bin/bash

set -euo pipefail

HOSTED_ZONE_ID=${1:-}
RECORD_NAME=${2:-}
PRIMARY_NLB=${3:-}
SECONDARY_NLB=${4:-}

if [[ -z "${HOSTED_ZONE_ID}" || -z "${RECORD_NAME}" || -z "${PRIMARY_NLB}" || -z "${SECONDARY_NLB}" ]]; then
  echo "Usage: $0 <hosted-zone-id> <record-name> <site-a-nlb-dns> <site-b-nlb-dns>"
  echo "Example: $0 Z1234567890 mq.example.com a123.elb.amazonaws.com b456.elb.amazonaws.com"
  exit 1
fi

HC_ID=$(aws route53 create-health-check \
  --caller-reference "mq-primary-$(date +%s)" \
  --health-check-config "IPAddress=,Port=1414,Type=TCP,FullyQualifiedDomainName=${PRIMARY_NLB},RequestInterval=30,FailureThreshold=3" \
  --query 'HealthCheck.Id' \
  --output text)

cat > /tmp/mq-failover-records.json <<EOF
{
  "Comment": "Create MQ failover records",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${RECORD_NAME}",
        "Type": "CNAME",
        "SetIdentifier": "mq-site-a-primary",
        "Failover": "PRIMARY",
        "TTL": 30,
        "HealthCheckId": "${HC_ID}",
        "ResourceRecords": [{"Value": "${PRIMARY_NLB}"}]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${RECORD_NAME}",
        "Type": "CNAME",
        "SetIdentifier": "mq-site-b-secondary",
        "Failover": "SECONDARY",
        "TTL": 30,
        "ResourceRecords": [{"Value": "${SECONDARY_NLB}"}]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --change-batch file:///tmp/mq-failover-records.json

rm -f /tmp/mq-failover-records.json

echo "✅ Route53 failover records created"
echo "Primary health check: ${HC_ID}"
