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
command -v docker >/dev/null 2>&1 || { echo "docker is required but not installed (needed for FluentD custom image)."; exit 1; }

# Verify cluster connection
echo "Verifying cluster connection..."
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Error: Cannot connect to Kubernetes cluster. Run 'aws eks update-kubeconfig' first."
  exit 1
fi
echo "Connected to cluster: $(kubectl config current-context)"
echo ""

# Step 1: Create namespace
echo "[1/8] Creating namespace..."
kubectl apply -f ${ROOT_DIR}/namespace.yaml
echo ""

# Step 2: Add Helm repositories
echo "[2/8] Adding Helm repositories..."
helm repo add elastic https://helm.elastic.co 2>/dev/null || true
helm repo add fluent https://fluent.github.io/helm-charts 2>/dev/null || true
helm repo update
echo ""

# Step 3: Setup IRSA for FluentD (dev only)
# For staging/prod, IAM automation (MRP25BUBUN-6) should handle this
if [[ "${ENVIRONMENT}" == "dev" ]]; then
  echo "[3/8] Setting up IRSA for FluentD (dev only)..."
  ${ROOT_DIR}/iam/irsa-setup.sh ${ENVIRONMENT}
  echo ""
else
  echo "[3/8] Skipping IRSA setup (staging/prod uses IAM automation)..."
  echo ""
fi

# Step 4: Deploy Elasticsearch
echo "[4/8] Deploying Elasticsearch..."
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
# The pre-install hook creates an ES token secret, so we create a dummy one manually
# Staging/Prod have ES security enabled, so hooks work correctly
echo "[5/8] Deploying Kibana..."
HOOKS_FLAG=""
if [[ "${ENVIRONMENT}" == "dev" ]]; then
  HOOKS_FLAG="--no-hooks"
  echo "Creating dummy secrets (dev only - ES security disabled)..."
  # Kibana chart unconditionally mounts elasticsearch-master-certs;
  # with createCert: false on ES, the chart doesn't generate it
  kubectl create secret generic elasticsearch-master-certs \
    --from-literal=ca.crt="" \
    --namespace ${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic kibana-${ENVIRONMENT}-kibana-es-token \
    --from-literal=token="" \
    --namespace ${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -
fi
# For staging/prod, substitute KIBANA_ENCRYPTION_KEY (generate if not set)
KIBANA_VALUES="${ROOT_DIR}/helm/kibana/values-${ENVIRONMENT}.yaml"
if [[ "${ENVIRONMENT}" != "dev" ]]; then
  KIBANA_ENCRYPTION_KEY=${KIBANA_ENCRYPTION_KEY:-$(openssl rand -hex 16)}
  sed "s/\${KIBANA_ENCRYPTION_KEY}/${KIBANA_ENCRYPTION_KEY}/g" \
    ${KIBANA_VALUES} > /tmp/kibana-values-${ENVIRONMENT}.yaml
  KIBANA_VALUES="/tmp/kibana-values-${ENVIRONMENT}.yaml"
fi
helm upgrade --install kibana-${ENVIRONMENT} elastic/kibana \
  --namespace ${NAMESPACE} \
  --values ${KIBANA_VALUES} \
  ${HOOKS_FLAG} \
  --wait \
  --timeout 5m
rm -f /tmp/kibana-values-${ENVIRONMENT}.yaml
echo ""

# Step 6: Create Kibana auth secret and apply ingress
echo "[6/8] Setting up Kibana authentication and ingress..."
${SCRIPT_DIR}/create-kibana-secret.sh ${ENVIRONMENT}
kubectl apply -f ${ROOT_DIR}/manifests/kibana-ingress-${ENVIRONMENT}.yaml
echo ""

# Step 7: Build and push custom FluentD image (ES + S3 plugins)
echo "[7/8] Building custom FluentD image..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/fluentd-es-s3"

# Login to ECR
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create ECR repo if it doesn't exist
aws ecr describe-repositories --repository-names fluentd-es-s3 --region ${AWS_REGION} 2>/dev/null || \
  aws ecr create-repository --repository-name fluentd-es-s3 \
    --image-scanning-configuration scanOnPush=true --region ${AWS_REGION}

# Build and push
docker build -t ${ECR_REPO}:v1.16-es8-s3 \
  -f ${ROOT_DIR}/docker/fluentd/Dockerfile .
docker push ${ECR_REPO}:v1.16-es8-s3
echo ""

# Step 8: Deploy FluentD
echo "[8/8] Deploying FluentD..."

# Create values file with substituted account ID
sed "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" \
  ${ROOT_DIR}/helm/fluentd/values-${ENVIRONMENT}.yaml > /tmp/fluentd-values-${ENVIRONMENT}.yaml

helm upgrade --install fluentd-${ENVIRONMENT} fluent/fluentd \
  --namespace ${NAMESPACE} \
  --values /tmp/fluentd-values-${ENVIRONMENT}.yaml \
  --set image.pullPolicy=Always \
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
