#!/bin/bash

set -euo pipefail

SITE_A_CONTEXT=${1:-}
SITE_B_CONTEXT=${2:-}

if [[ -z "${SITE_A_CONTEXT}" || -z "${SITE_B_CONTEXT}" ]]; then
  echo "Usage: $0 <site-a-kube-context> <site-b-kube-context>"
  exit 1
fi

echo "=== SITE A ==="
kubectl --context "${SITE_A_CONTEXT}" get pods -n ibm-mq -o wide
kubectl --context "${SITE_A_CONTEXT}" get svc -n ibm-mq mq-ha-service

echo ""
echo "=== SITE B ==="
kubectl --context "${SITE_B_CONTEXT}" get pods -n ibm-mq -o wide
kubectl --context "${SITE_B_CONTEXT}" get svc -n ibm-mq mq-ha-service
