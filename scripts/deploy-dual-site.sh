#!/bin/bash

set -euo pipefail

SITE_A_CONTEXT=${1:-}
SITE_B_CONTEXT=${2:-}

if [[ -z "${SITE_A_CONTEXT}" || -z "${SITE_B_CONTEXT}" ]]; then
  echo "Usage: $0 <site-a-kube-context> <site-b-kube-context>"
  echo "Example: $0 arn:aws:eks:us-east-1:111111111111:cluster/mq-ha-site-a arn:aws:eks:us-west-2:111111111111:cluster/mq-ha-site-b"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/deploy-site-mq-ha.sh" site-a "${SITE_A_CONTEXT}"
"${SCRIPT_DIR}/deploy-site-mq-ha.sh" site-b "${SITE_B_CONTEXT}"

echo ""
echo "✅ Dual-site MQ Native HA deployment submitted"
