#!/bin/bash

set -euo pipefail

SITE_A_CONTEXT=${1:-}
SITE_B_CONTEXT=${2:-}

if [[ -z "${SITE_A_CONTEXT}" || -z "${SITE_B_CONTEXT}" ]]; then
  echo "Usage: $0 <site-a-kube-context> <site-b-kube-context>"
  exit 1
fi

SITE_A_NLB=$(kubectl --context "${SITE_A_CONTEXT}" get svc -n ibm-mq mq-ha-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
SITE_B_NLB=$(kubectl --context "${SITE_B_CONTEXT}" get svc -n ibm-mq mq-ha-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Site A NLB: ${SITE_A_NLB}"
echo "Site B NLB: ${SITE_B_NLB}"
