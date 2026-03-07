#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "ℹ️  This script deploys only one site using the legacy manifests in k8s/."
echo "ℹ️  For dual-site deployment (site-a + site-b), use: ./deploy-dual-site.sh <site-a-context> <site-b-context>"
echo ""
echo "🚀 Deploying IBM MQ Native HA (single-site legacy mode)..."

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ kubectl is not configured. Please configure kubectl first."
    echo "Run: aws eks update-kubeconfig --name mq-ha-learning-cluster --region us-east-1"
    exit 1
fi

# Navigate to k8s directory
K8S_DIR="${SCRIPT_DIR}/../k8s"

echo "📁 Using Kubernetes manifests from: ${K8S_DIR}"

# Create namespace
echo "📦 Creating namespace..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"

# Create storage class
echo "💾 Creating storage class..."
kubectl apply -f "${K8S_DIR}/storage-class.yaml"

# Create configmap
echo "⚙️  Creating ConfigMap..."
kubectl apply -f "${K8S_DIR}/mq-configmap.yaml"

# Create secret
echo "🔐 Creating Secret..."
kubectl apply -f "${K8S_DIR}/mq-secret.yaml"

# Deploy StatefulSet
echo "🎯 Deploying MQ StatefulSet..."
kubectl apply -f "${K8S_DIR}/mq-statefulset.yaml"

echo ""
echo "✅ Deployment initiated!"
echo ""
echo "📊 Monitor the deployment with:"
echo "   kubectl get pods -n ibm-mq -w"
echo ""
echo "🔍 Check status:"
echo "   kubectl get all -n ibm-mq"
echo ""
echo "📝 View logs:"
echo "   kubectl logs -n ibm-mq mq-ha-0 -f"
echo ""
echo "🌐 Get LoadBalancer URL (after pods are running):"
echo "   kubectl get svc -n ibm-mq mq-ha-service"
echo ""
echo "⏳ Note: It may take 5-10 minutes for all pods to be ready."
