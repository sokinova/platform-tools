#!/bin/bash
# EFK Stack Deployment Script
# Deploys Elasticsearch, Kibana, and FluentD to an EKS cluster using custom Helm chart

set -e

# Configuration
ENVIRONMENT=${1:-dev}
AWS_REGION=${AWS_REGION:-us-east-1}
NAMESPACE="logging"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
CHART_DIR="${ROOT_DIR}/chart"
VALUES_FILE="${CHART_DIR}/values/${ENVIRONMENT}-values.yaml"

echo "=========================================="
echo "EFK Stack Deployment - ${ENVIRONMENT}"
echo "=========================================="
echo ""

# Validate environment
if [[ ! "${ENVIRONMENT}" =~ ^(dev|staging|prod)$ ]]; then
  echo "Error: Invalid environment '${ENVIRONMENT}'. Must be dev, staging, or prod."
  exit 1
fi

# Validate values file exists
if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "Error: Values file not found: ${VALUES_FILE}"
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

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo ""

# Step 1: Setup IRSA for FluentD (dev only)
# For staging/prod, IAM automation (MRP25BUBUN-6) should handle this
if [[ "${ENVIRONMENT}" == "dev" ]]; then
  echo "[1/5] Setting up IRSA for FluentD (dev only)..."
  ${ROOT_DIR}/iam/irsa-setup.sh ${ENVIRONMENT}
  echo ""
else
  echo "[1/5] Skipping IRSA setup (staging/prod uses IAM automation)..."
  echo ""
fi

# Step 2: Build and push custom FluentD image
echo "[2/5] Building custom FluentD image..."
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

# Step 3: Deploy EFK chart
echo "[3/5] Deploying EFK Helm chart..."
HELM_SET_ARGS="--set aws.accountId=${AWS_ACCOUNT_ID}"

# Generate encryption key for non-dev environments
if [[ "${ENVIRONMENT}" != "dev" ]]; then
  KIBANA_ENCRYPTION_KEY="${KIBANA_ENCRYPTION_KEY:-$(openssl rand -hex 16)}"
  HELM_SET_ARGS="${HELM_SET_ARGS} --set kibana.security.encryptionKey=${KIBANA_ENCRYPTION_KEY}"
fi

helm upgrade --install efk-${ENVIRONMENT} ${CHART_DIR} \
  --namespace ${NAMESPACE} --create-namespace \
  --values ${VALUES_FILE} \
  ${HELM_SET_ARGS} \
  --wait --timeout 15m
echo ""

# Step 4: Create Kibana auth secret
echo "[4/5] Setting up Kibana authentication..."
${SCRIPT_DIR}/create-kibana-secret.sh ${ENVIRONMENT}
echo ""

# Step 5: Verify
echo "[5/5] Verifying deployment..."
kubectl get pods -n ${NAMESPACE}
echo ""

# Summary
echo "=========================================="
echo "EFK Stack Deployment Complete!"
echo "=========================================="
echo ""
echo "Components deployed:"
echo "  - Elasticsearch: efk-${ENVIRONMENT}-elasticsearch"
echo "  - Kibana: efk-${ENVIRONMENT}-kibana"
echo "  - FluentD: efk-${ENVIRONMENT}-fluentd"
echo ""
echo "Kibana URL: http://kibana-ubuntu-${ENVIRONMENT}.312ubuntu.com (once DNS is configured)"
echo ""
echo "Run tests:"
echo "  ${SCRIPT_DIR}/test-logging.sh ${ENVIRONMENT}"
