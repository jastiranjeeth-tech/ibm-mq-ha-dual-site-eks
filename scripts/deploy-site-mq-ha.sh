#!/bin/bash

set -euo pipefail

SITE=${1:-}
KUBE_CONTEXT=${2:-}

if [[ -z "${SITE}" ]]; then
  echo "Usage: $0 <site-a|site-b> [kube-context]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s/${SITE}"

if [[ ! -d "${K8S_DIR}" ]]; then
  echo "❌ Unknown site '${SITE}'. Expected site-a or site-b"
  exit 1
fi

KCTX_ARGS=()
if [[ -n "${KUBE_CONTEXT}" ]]; then
  KCTX_ARGS=(--context "${KUBE_CONTEXT}")
  echo "🎯 Using context: ${KUBE_CONTEXT}"
fi

echo "🚀 Deploying IBM MQ Native HA for ${SITE}"
echo "📁 Manifests: ${K8S_DIR}"

kubectl "${KCTX_ARGS[@]}" apply -f "${K8S_DIR}/namespace.yaml"
kubectl "${KCTX_ARGS[@]}" apply -f "${K8S_DIR}/storage-class.yaml"
kubectl "${KCTX_ARGS[@]}" apply -f "${K8S_DIR}/mq-configmap.yaml"
kubectl "${KCTX_ARGS[@]}" apply -f "${K8S_DIR}/mq-secret.yaml"

# Check if StatefulSet exists and delete it if volumeClaimTemplates changed
if kubectl "${KCTX_ARGS[@]}" get statefulset mq-ha -n ibm-mq &>/dev/null; then
  echo "⚠️  StatefulSet exists. Deleting to allow volumeClaimTemplates update..."
  kubectl "${KCTX_ARGS[@]}" delete statefulset mq-ha -n ibm-mq --cascade=orphan
  echo "✓ StatefulSet deleted (pods preserved)"
fi

kubectl "${KCTX_ARGS[@]}" apply -f "${K8S_DIR}/mq-statefulset.yaml"

echo ""
echo "✅ ${SITE} deployment submitted"
echo "Monitor: kubectl ${KUBE_CONTEXT:+--context ${KUBE_CONTEXT}} get pods -n ibm-mq -w"
echo "NLB:     kubectl ${KUBE_CONTEXT:+--context ${KUBE_CONTEXT}} get svc -n ibm-mq mq-ha-service"
