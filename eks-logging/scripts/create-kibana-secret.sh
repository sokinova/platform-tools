#!/bin/bash
# ============================================================
# Kibana Basic Auth Secret Creator
# ============================================================
# Creates a Kubernetes secret with htpasswd-formatted credentials for Kibana ingress.
# The nginx ingress controller uses this secret for basic auth (password prompt).
#
# Credential flow:
#   1. Check AWS SecretsManager for existing credentials
#   2. If found, use them. If not, generate random credentials and store them.
#   3. Format credentials as htpasswd (Apache-style hash)
#   4. Create/update the K8s secret in the logging namespace
#
# The ingress template references this secret via the annotation:
#   nginx.ingress.kubernetes.io/auth-secret: kibana-basic-auth
#
# Usage:
#   ./create-kibana-secret.sh dev
#   ./create-kibana-secret.sh staging
# ============================================================

set -e

# Configuration
ENVIRONMENT=${1:-dev}
NAMESPACE="logging"
SECRET_NAME="kibana-basic-auth"
AWS_SECRET_NAME="eks/logging/kibana-credentials-${ENVIRONMENT}"
AWS_REGION=${AWS_REGION:-us-east-1}

echo "Creating Kibana auth secret for ${ENVIRONMENT} environment..."

# Check if credentials already exist in AWS SecretsManager
if aws secretsmanager describe-secret --secret-id "${AWS_SECRET_NAME}" --region ${AWS_REGION} >/dev/null 2>&1; then
  # Fetch existing credentials from SecretsManager
  echo "Fetching credentials from SecretsManager..."
  CREDS=$(aws secretsmanager get-secret-value \
    --secret-id "${AWS_SECRET_NAME}" \
    --region ${AWS_REGION} \
    --query SecretString \
    --output text)

  # Parse the JSON secret to extract username and password
  USERNAME=$(echo "${CREDS}" | jq -r '.username')
  PASSWORD=$(echo "${CREDS}" | jq -r '.password')
else
  # No existing secret — generate default credentials
  echo "Warning: Secret '${AWS_SECRET_NAME}' not found in SecretsManager."
  echo "Creating default credentials (change these in production!)..."

  # Generate a random 12-character password
  USERNAME="admin"
  PASSWORD=$(openssl rand -base64 12)

  # Store the generated credentials in SecretsManager for future use
  echo "Storing credentials in SecretsManager..."
  aws secretsmanager create-secret \
    --name "${AWS_SECRET_NAME}" \
    --secret-string "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}" \
    --region ${AWS_REGION} 2>/dev/null || \
  aws secretsmanager put-secret-value \
    --secret-id "${AWS_SECRET_NAME}" \
    --secret-string "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}" \
    --region ${AWS_REGION}

  # Only print credentials in interactive terminals (not in CI logs)
  if [[ -t 1 ]]; then
    echo ""
    echo "Generated credentials:"
    echo "  Username: ${USERNAME}"
    echo "  Password: ${PASSWORD}"
    echo ""
  else
    echo "Credentials stored in SecretsManager: ${AWS_SECRET_NAME}"
  fi
fi

# Generate htpasswd-formatted credentials for nginx ingress
if command -v htpasswd >/dev/null 2>&1; then
  # Use htpasswd if available (produces bcrypt hash)
  HTPASSWD=$(htpasswd -nb "${USERNAME}" "${PASSWORD}")
else
  # Fall back to openssl for apr1 hash if htpasswd is not installed
  echo "htpasswd not found, using openssl..."
  SALT=$(openssl rand -base64 3)
  HASH=$(openssl passwd -apr1 -salt "${SALT}" "${PASSWORD}")
  HTPASSWD="${USERNAME}:${HASH}"
fi

# Create or update the Kubernetes secret using dry-run + apply pattern
# This is idempotent — it creates the secret if missing, or updates it if it exists
echo "Creating Kubernetes secret..."
kubectl create secret generic ${SECRET_NAME} \
  --from-literal=auth="${HTPASSWD}" \
  --namespace ${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Kibana auth secret created successfully!"
echo "Secret: ${NAMESPACE}/${SECRET_NAME}"
