#!/bin/bash
# Create Kibana basic auth secret from AWS SecretsManager
# Fetches credentials and creates Kubernetes secret with htpasswd format

set -e

# Configuration
ENVIRONMENT=${1:-dev}
NAMESPACE="logging"
SECRET_NAME="kibana-basic-auth"
AWS_SECRET_NAME="eks/logging/kibana-credentials-${ENVIRONMENT}"
AWS_REGION=${AWS_REGION:-us-east-1}

echo "Creating Kibana auth secret for ${ENVIRONMENT} environment..."

# Check if secret exists in SecretsManager
if aws secretsmanager describe-secret --secret-id "${AWS_SECRET_NAME}" --region ${AWS_REGION} >/dev/null 2>&1; then
  echo "Fetching credentials from SecretsManager..."
  CREDS=$(aws secretsmanager get-secret-value \
    --secret-id "${AWS_SECRET_NAME}" \
    --region ${AWS_REGION} \
    --query SecretString \
    --output text)

  USERNAME=$(echo "${CREDS}" | jq -r '.username')
  PASSWORD=$(echo "${CREDS}" | jq -r '.password')
else
  echo "Warning: Secret '${AWS_SECRET_NAME}' not found in SecretsManager."
  echo "Creating default credentials (change these in production!)..."

  # Generate random password for initial setup
  USERNAME="admin"
  PASSWORD=$(openssl rand -base64 12)

  # Store generated credentials in SecretsManager automatically
  echo "Storing credentials in SecretsManager..."
  aws secretsmanager create-secret \
    --name "${AWS_SECRET_NAME}" \
    --secret-string "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}" \
    --region ${AWS_REGION} 2>/dev/null || \
  aws secretsmanager put-secret-value \
    --secret-id "${AWS_SECRET_NAME}" \
    --secret-string "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}" \
    --region ${AWS_REGION}

  # Only print credentials interactively (not in CI logs)
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

# Check if htpasswd is available
if command -v htpasswd >/dev/null 2>&1; then
  # Generate htpasswd format
  HTPASSWD=$(htpasswd -nb "${USERNAME}" "${PASSWORD}")
else
  # Use openssl as fallback
  echo "htpasswd not found, using openssl..."
  SALT=$(openssl rand -base64 3)
  HASH=$(openssl passwd -apr1 -salt "${SALT}" "${PASSWORD}")
  HTPASSWD="${USERNAME}:${HASH}"
fi

# Create or update Kubernetes secret
echo "Creating Kubernetes secret..."
kubectl create secret generic ${SECRET_NAME} \
  --from-literal=auth="${HTPASSWD}" \
  --namespace ${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Kibana auth secret created successfully!"
echo "Secret: ${NAMESPACE}/${SECRET_NAME}"
