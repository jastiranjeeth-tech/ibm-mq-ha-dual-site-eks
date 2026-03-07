#!/bin/bash

set -e

echo "🧹 Cleaning up IBM MQ HA resources..."

# Check if namespace exists
if ! kubectl get namespace ibm-mq &> /dev/null; then
    echo "✅ Namespace 'ibm-mq' does not exist. Nothing to clean up."
    exit 0
fi

echo "⚠️  This will delete all MQ resources in the 'ibm-mq' namespace."
read -p "Are you sure you want to continue? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 1
fi

# Navigate to k8s directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
K8S_DIR="${SCRIPT_DIR}/../k8s"

echo "📁 Using Kubernetes manifests from: ${K8S_DIR}"

# Delete StatefulSet and Services
echo "🗑️  Deleting StatefulSet and Services..."
kubectl delete -f "${K8S_DIR}/mq-statefulset.yaml" --ignore-not-found=true

# Wait for pods to terminate
echo "⏳ Waiting for pods to terminate..."
kubectl wait --for=delete pod -n ibm-mq -l app=mq-ha --timeout=120s 2>/dev/null || true

# Delete PVCs
echo "💾 Deleting Persistent Volume Claims..."
kubectl delete pvc -n ibm-mq -l app=mq-ha --ignore-not-found=true

# Delete ConfigMap and Secret
echo "🗑️  Deleting ConfigMap and Secret..."
kubectl delete -f "${K8S_DIR}/mq-configmap.yaml" --ignore-not-found=true
kubectl delete -f "${K8S_DIR}/mq-secret.yaml" --ignore-not-found=true

# Delete StorageClass
echo "🗑️  Deleting StorageClass..."
kubectl delete -f "${K8S_DIR}/storage-class.yaml" --ignore-not-found=true

# Delete namespace
echo "🗑️  Deleting namespace..."
kubectl delete -f "${K8S_DIR}/namespace.yaml" --ignore-not-found=true

echo ""
echo "✅ Cleanup completed!"
echo ""
echo "📋 Remaining resources:"
kubectl get pv | grep mq-ha || echo "   No MQ persistent volumes found"
echo ""
echo "💡 Note: If you want to completely remove the EKS cluster, run:"
echo "   cd ../terraform && terraform destroy"
