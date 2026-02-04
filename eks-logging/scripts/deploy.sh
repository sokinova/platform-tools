#!/bin/bash
# EFK Stack Deployment Script
# Deploys Elasticsearch, Kibana, and FluentD to an EKS cluster

set -e

# Configuration
ENVIRONMENT=${1:-dev}
AWS_REGION=${AWS_REGION:-us-east-1}
NAMESPACE="logging"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"

echo "=========================================="
echo "EFK Stack Deployment - ${ENVIRONMENT}"
echo "=========================================="
echo ""

# Validate environment
if [[ ! "${ENVIRONMENT}" =~ ^(dev|staging|prod)$ ]]; then
  echo "Error: Invalid environment '${ENVIRONMENT}'. Must be dev, staging, or prod."
  exit 1
fi

# Check prerequisites
echo "Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed."; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws CLI is required but not installed."; exit 1; }

# Verify cluster connection
echo "Verifying cluster connection..."
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Error: Cannot connect to Kubernetes cluster. Run 'aws eks update-kubeconfig' first."
  exit 1
fi
echo "Connected to cluster: $(kubectl config current-context)"
echo ""

# Step 1: Create namespace
echo "[1/7] Creating namespace..."
kubectl apply -f ${ROOT_DIR}/namespace.yaml
echo ""

# Step 2: Add Helm repositories
echo "[2/7] Adding Helm repositories..."
helm repo add elastic https://helm.elastic.co 2>/dev/null || true
helm repo add fluent https://fluent.github.io/helm-charts 2>/dev/null || true
helm repo update
echo ""

# Step 3: Setup IRSA for FluentD (dev only)
# For staging/prod, IAM automation (MRP25BUBUN-6) should handle this
if [[ "${ENVIRONMENT}" == "dev" ]]; then
  echo "[3/7] Setting up IRSA for FluentD (dev only)..."
  ${ROOT_DIR}/iam/irsa-setup.sh ${ENVIRONMENT}
  echo ""
else
  echo "[3/7] Skipping IRSA setup (staging/prod uses IAM automation)..."
  echo ""
fi

# Step 4: Deploy Elasticsearch
echo "[4/7] Deploying Elasticsearch..."
helm upgrade --install elasticsearch-${ENVIRONMENT} elastic/elasticsearch \
  --namespace ${NAMESPACE} \
  --values ${ROOT_DIR}/helm/elasticsearch/values-${ENVIRONMENT}.yaml \
  --wait \
  --timeout 10m
echo ""

# Wait for Elasticsearch to be ready
echo "Waiting for Elasticsearch to be ready..."
kubectl wait --for=condition=ready pod \
  -l app=elasticsearch-master \
  -n ${NAMESPACE} \
  --timeout=300s
echo ""

# Step 5: Deploy Kibana
# NOTE: Dev uses --no-hooks because ES security is disabled (HTTP not HTTPS)
# Staging/Prod have ES security enabled, so hooks work correctly
echo "[5/7] Deploying Kibana..."
HOOKS_FLAG=""
if [[ "${ENVIRONMENT}" == "dev" ]]; then
  HOOKS_FLAG="--no-hooks"
fi
helm upgrade --install kibana-${ENVIRONMENT} elastic/kibana \
  --namespace ${NAMESPACE} \
  --values ${ROOT_DIR}/helm/kibana/values-${ENVIRONMENT}.yaml \
  ${HOOKS_FLAG} \
  --wait \
  --timeout 5m
echo ""

# Step 6: Create Kibana auth secret and apply ingress
echo "[6/7] Setting up Kibana authentication and ingress..."
${SCRIPT_DIR}/create-kibana-secret.sh ${ENVIRONMENT}
kubectl apply -f ${ROOT_DIR}/manifests/kibana-ingress-${ENVIRONMENT}.yaml
echo ""

# Step 7: Deploy FluentD
echo "[7/7] Deploying FluentD..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create values file with substituted account ID
sed "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" \
  ${ROOT_DIR}/helm/fluentd/values-${ENVIRONMENT}.yaml > /tmp/fluentd-values-${ENVIRONMENT}.yaml

helm upgrade --install fluentd-${ENVIRONMENT} fluent/fluentd \
  --namespace ${NAMESPACE} \
  --values /tmp/fluentd-values-${ENVIRONMENT}.yaml \
  --wait \
  --timeout 5m

rm -f /tmp/fluentd-values-${ENVIRONMENT}.yaml
echo ""

# Summary
echo "=========================================="
echo "EFK Stack Deployment Complete!"
echo "=========================================="
echo ""
echo "Components deployed:"
echo "  - Elasticsearch: elasticsearch-${ENVIRONMENT}-master"
echo "  - Kibana: kibana-${ENVIRONMENT}-kibana"
echo "  - FluentD: fluentd-${ENVIRONMENT}"
echo ""
echo "Kibana URL: http://kibana-ubuntu-dev.312ubuntu.com (once DNS is configured)"
echo ""
echo "Verify deployment:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo ""
echo "Run tests:"
echo "  ${SCRIPT_DIR}/test-logging.sh ${ENVIRONMENT}"
