#!/bin/bash

set -e

echo "🧪 Testing IBM MQ Connection..."

# Check if namespace exists
if ! kubectl get namespace ibm-mq &> /dev/null; then
    echo "❌ Namespace 'ibm-mq' not found. Please deploy MQ first."
    exit 1
fi

# Check if pods are running
READY_PODS=$(kubectl get pods -n ibm-mq -l app=mq-ha --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [ "$READY_PODS" -eq 0 ]; then
    echo "❌ No MQ pods are running. Please check deployment."
    exit 1
fi

echo "✅ Found ${READY_PODS} running MQ pod(s)"

# Get the first running pod
POD_NAME=$(kubectl get pods -n ibm-mq -l app=mq-ha --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')

echo "📡 Using pod: ${POD_NAME}"
echo ""

# Display queue manager status
echo "🔍 Queue Manager Status:"
kubectl exec -n ibm-mq "${POD_NAME}" -- dspmq
echo ""

# Test putting a message
echo "📤 Sending test message..."
echo "Test message from $(date)" | kubectl exec -i -n ibm-mq "${POD_NAME}" -- /opt/mqm/samp/bin/amqsput TEST.QUEUE QMHA
echo "✅ Message sent to TEST.QUEUE"
echo ""

# Test getting the message
echo "📥 Retrieving test message..."
kubectl exec -n ibm-mq "${POD_NAME}" -- /opt/mqm/samp/bin/amqsget TEST.QUEUE QMHA
echo ""

# Get service details
echo "🌐 Service Information:"
kubectl get svc -n ibm-mq mq-ha-service
echo ""

# Get external endpoint if available
EXTERNAL_IP=$(kubectl get svc -n ibm-mq mq-ha-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$EXTERNAL_IP" ]; then
    echo "🔗 External Access:"
    echo "   MQ Endpoint: ${EXTERNAL_IP}:1414"
    echo "   Web Console: https://${EXTERNAL_IP}:9443/ibmmq/console"
    echo "   Credentials: admin / passw0rd"
else
    echo "⏳ LoadBalancer external IP not yet assigned. Please wait and check again."
fi

echo ""
echo "✅ Connection test completed successfully!"
