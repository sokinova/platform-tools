#!/bin/bash
# IRSA (IAM Roles for Service Accounts) setup script for FluentD S3 access
# NOTE: This is a TEMPORARY setup for dev environment testing only.
#       For staging/prod, IAM automation (MRP25BUBUN-6) should handle this.

set -e

# Configuration - DEV ONLY
ENVIRONMENT=${1:-dev}

if [[ "${ENVIRONMENT}" != "dev" ]]; then
  echo "WARNING: This script is intended for dev environment only."
  echo "For staging/prod, IAM should be managed by MRP25BUBUN-6 (IAM automation)."
  # Skip interactive prompt in CI (non-interactive shells)
  if [[ -t 0 ]]; then
    read -p "Continue anyway? (y/N): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
      echo "Aborted."
      exit 1
    fi
  else
    echo "Running in non-interactive mode (CI), continuing..."
  fi
fi

CLUSTER_NAME="${CLUSTER_NAME:-projectx_cluster_ubuntu25b}"
AWS_REGION=${AWS_REGION:-us-east-1}
NAMESPACE="logging"
SERVICE_ACCOUNT_NAME="fluentd-${ENVIRONMENT}"
POLICY_NAME="fluentd-s3-${ENVIRONMENT}"
ROLE_NAME="fluentd-s3-${ENVIRONMENT}"

echo "Setting up IRSA for FluentD in ${ENVIRONMENT} environment..."
echo "NOTE: This is temporary for dev testing. Staging/prod should use IAM automation."
echo ""

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"

# Get OIDC Provider URL
OIDC_PROVIDER=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
  --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

if [ -z "${OIDC_PROVIDER}" ]; then
  echo "Error: Could not get OIDC provider for cluster ${CLUSTER_NAME}"
  exit 1
fi
echo "OIDC Provider: ${OIDC_PROVIDER}"

# Check if OIDC provider is already associated
OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn ${OIDC_PROVIDER_ARN} 2>/dev/null; then
  echo "Creating OIDC provider..."
  eksctl utils associate-iam-oidc-provider \
    --cluster ${CLUSTER_NAME} \
    --region ${AWS_REGION} \
    --approve
fi

# Create IAM policy
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Substitute environment-specific bucket name in the policy template
S3_BUCKET="eks-logs-312ubuntu-${ENVIRONMENT}"
POLICY_FILE=$(mktemp)
sed "s/eks-logs-312ubuntu-dev/${S3_BUCKET}/g" ${SCRIPT_DIR}/fluentd-s3-policy.json > ${POLICY_FILE}

if aws iam get-policy --policy-arn ${POLICY_ARN} 2>/dev/null; then
  echo "Policy ${POLICY_NAME} already exists, updating..."
  POLICY_VERSION=$(aws iam list-policy-versions --policy-arn ${POLICY_ARN} \
    --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text | head -1)
  if [ -n "${POLICY_VERSION}" ]; then
    aws iam delete-policy-version --policy-arn ${POLICY_ARN} --version-id ${POLICY_VERSION}
  fi
  aws iam create-policy-version \
    --policy-arn ${POLICY_ARN} \
    --policy-document file://${POLICY_FILE} \
    --set-as-default
else
  echo "Creating policy ${POLICY_NAME}..."
  aws iam create-policy \
    --policy-name ${POLICY_NAME} \
    --policy-document file://${POLICY_FILE}
fi
rm -f ${POLICY_FILE}

# Create trust policy document
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT_NAME}"
        }
      }
    }
  ]
}
EOF
)

# Create or update IAM role
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
if aws iam get-role --role-name ${ROLE_NAME} 2>/dev/null; then
  echo "Role ${ROLE_NAME} already exists, updating trust policy..."
  aws iam update-assume-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-document "${TRUST_POLICY}"
else
  echo "Creating role ${ROLE_NAME}..."
  aws iam create-role \
    --role-name ${ROLE_NAME} \
    --assume-role-policy-document "${TRUST_POLICY}" \
    --description "Temporary IAM role for FluentD S3 access in ${ENVIRONMENT} (dev testing)"
fi

# Attach policy to role
echo "Attaching policy to role..."
aws iam attach-role-policy \
  --role-name ${ROLE_NAME} \
  --policy-arn ${POLICY_ARN}

echo ""
echo "IRSA setup complete!"
echo "Role ARN: ${ROLE_ARN}"
echo ""
echo "NOTE: This is a temporary setup for dev testing."
echo "For staging/prod, coordinate with MRP25BUBUN-6 (IAM automation)."
