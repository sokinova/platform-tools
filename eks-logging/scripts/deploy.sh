#!/bin/bash
# ============================================================
# EFK Stack Deployment Script
# ============================================================
# Deploys the full EFK logging stack (Elasticsearch, Kibana, FluentD)
# to an EKS cluster using three separate Helm charts.
#
# Deploy order is important:
#   1. IRSA setup — creates IAM role for FluentD S3 access
#   2. ECR build  — builds and pushes custom FluentD Docker image
#   3. Elasticsearch — must be first (creates the namespace and the ES service)
#   4. Kibana — depends on ES being available
#   5. FluentD — depends on ES being available and IRSA being configured
#   6. Auth secret — creates the basic-auth K8s secret for Kibana ingress
#
# Usage:
#   ./deploy.sh dev              # Deploy to dev environment
#   ./deploy.sh staging          # Deploy to staging environment
#   ./deploy.sh prod             # Deploy to prod environment
# ============================================================

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

# Validate environment argument
if [[ ! "${ENVIRONMENT}" =~ ^(dev|staging|prod)$ ]]; then
  echo "Error: Invalid environment '${ENVIRONMENT}'. Must be dev, staging, or prod."
  exit 1
fi

# Check that required CLI tools are installed
echo "Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed."; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws CLI is required but not installed."; exit 1; }

# Verify we can talk to a K8s cluster
echo "Verifying cluster connection..."
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Error: Cannot connect to Kubernetes cluster. Run 'aws eks update-kubeconfig' first."
  exit 1
fi
echo "Connected to cluster: $(kubectl config current-context)"
echo ""

# Get AWS Account ID (needed for ECR image URL and IRSA role ARN)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo ""

# Step 1: Setup IRSA for FluentD (dev only — staging/prod uses IAM automation)
if [[ "${ENVIRONMENT}" == "dev" ]]; then
  echo "[1/6] Setting up IRSA for FluentD (dev only)..."
  ${ROOT_DIR}/iam/irsa-setup.sh ${ENVIRONMENT}
  echo ""
else
  echo "[1/6] Skipping IRSA setup (staging/prod uses IAM automation)..."
  echo ""
fi

# Step 2: Build and push the custom FluentD Docker image to ECR
echo "[2/6] Building custom FluentD image..."
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/fluentd-es-s3"

# Login to ECR
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create ECR repo if it doesn't exist (first-time setup)
aws ecr describe-repositories --repository-names fluentd-es-s3 --region ${AWS_REGION} 2>/dev/null || \
  aws ecr create-repository --repository-name fluentd-es-s3 \
    --image-scanning-configuration scanOnPush=true --region ${AWS_REGION}

# Build and push the image
docker build -t ${ECR_REPO}:v1.16-es8-s3 \
  -f ${ROOT_DIR}/docker/fluentd/Dockerfile .
docker push ${ECR_REPO}:v1.16-es8-s3
echo ""

# Step 3: Deploy Elasticsearch (creates the logging namespace)
echo "[3/6] Deploying Elasticsearch..."
helm upgrade --install elasticsearch-${ENVIRONMENT} ${ROOT_DIR}/helm-elasticsearch \
  --namespace ${NAMESPACE} --create-namespace \
  --values ${ROOT_DIR}/helm-elasticsearch/values/${ENVIRONMENT}-values.yaml \
  --wait --timeout 10m
echo ""

# Step 4: Deploy Kibana
echo "[4/6] Deploying Kibana..."
HELM_SET_ARGS=""
# Generate an encryption key for xpack when security is enabled (staging/prod)
if [[ "${ENVIRONMENT}" != "dev" ]]; then
  KIBANA_ENCRYPTION_KEY="${KIBANA_ENCRYPTION_KEY:-$(openssl rand -hex 16)}"
  HELM_SET_ARGS="--set kibana.security.encryptionKey=${KIBANA_ENCRYPTION_KEY}"
fi

helm upgrade --install kibana-${ENVIRONMENT} ${ROOT_DIR}/helm-kibana \
  --namespace ${NAMESPACE} \
  --values ${ROOT_DIR}/helm-kibana/values/${ENVIRONMENT}-values.yaml \
  ${HELM_SET_ARGS} \
  --wait --timeout 5m
echo ""

# Step 5: Deploy FluentD (pass AWS account ID for IRSA annotation in the ServiceAccount)
echo "[5/6] Deploying FluentD..."
helm upgrade --install fluentd-${ENVIRONMENT} ${ROOT_DIR}/helm-fluentd \
  --namespace ${NAMESPACE} \
  --values ${ROOT_DIR}/helm-fluentd/values/${ENVIRONMENT}-values.yaml \
  --set aws.accountId=${AWS_ACCOUNT_ID} \
  --wait --timeout 5m
echo ""

# Step 6: Create Kibana basic-auth secret and verify pods
echo "[6/6] Setting up Kibana authentication and verifying..."
${SCRIPT_DIR}/create-kibana-secret.sh ${ENVIRONMENT}
echo ""

# Show final pod status
kubectl get pods -n ${NAMESPACE}
echo ""

# Deployment summary
echo "=========================================="
echo "EFK Stack Deployment Complete!"
echo "=========================================="
echo ""
echo "Components deployed:"
echo "  - Elasticsearch: elasticsearch-${ENVIRONMENT}"
echo "  - Kibana: kibana-${ENVIRONMENT}"
echo "  - FluentD: fluentd-${ENVIRONMENT}"
echo ""
echo "Kibana URL: http://kibana-ubuntu-${ENVIRONMENT}.312ubuntu.com (once DNS is configured)"
echo ""
echo "Run tests:"
echo "  ${SCRIPT_DIR}/test-logging.sh ${ENVIRONMENT}"
