#!/usr/bin/env bash
set -euo pipefail

CERT_MANAGER_NS="cert-manager"

echo "======================================"
echo "🔐 Bootstrapping TLS (cert-manager)"
echo "======================================"

############################################
# 1️⃣ Install cert-manager if not present
############################################

if kubectl -n "${CERT_MANAGER_NS}" get deploy cert-manager >/dev/null 2>&1; then
  echo "✅ cert-manager already installed."
else
  echo "⚠️ cert-manager not found. Installing..."

  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
fi

echo "⏳ Waiting for cert-manager rollout..."

kubectl -n "${CERT_MANAGER_NS}" rollout status deploy/cert-manager --timeout=10m
kubectl -n "${CERT_MANAGER_NS}" rollout status deploy/cert-manager-webhook --timeout=10m
kubectl -n "${CERT_MANAGER_NS}" rollout status deploy/cert-manager-cainjector --timeout=10m

############################################
# 2️⃣ Annotate ServiceAccount for IRSA
############################################

echo "🔑 Ensuring cert-manager ServiceAccount has IAM role annotation..."

if [ -z "${CERT_MANAGER_ROUTE53_ROLE_ARN:-}" ]; then
  echo "❌ CERT_MANAGER_ROUTE53_ROLE_ARN is not set."
  exit 1
fi

kubectl annotate serviceaccount cert-manager \
  -n "${CERT_MANAGER_NS}" \
  eks.amazonaws.com/role-arn="${CERT_MANAGER_ROUTE53_ROLE_ARN}" \
  --overwrite

echo "🔄 Restarting cert-manager deployment to pick up new IAM role..."
kubectl -n "${CERT_MANAGER_NS}" rollout restart deploy/cert-manager
kubectl -n "${CERT_MANAGER_NS}" rollout status deploy/cert-manager --timeout=10m

############################################
# 3️⃣ Ensure ClusterIssuer exists
############################################

if kubectl get clusterissuer "${CLUSTERISSUER_NAME}" >/dev/null 2>&1; then
  echo "✅ ClusterIssuer '${CLUSTERISSUER_NAME}' already exists."
else
  echo "⚠️ Creating ClusterIssuer..."

  sed "s/HOSTED_ZONE_PLACEHOLDER/${HOSTED_ZONE_ID}/g" \
    "${CLUSTER_ISSUER_MANIFEST}" | kubectl apply -f -
fi

############################################
# 4️⃣ Ensure Wildcard Certificate exists
############################################

if kubectl -n "${WILDCARD_SECRET_NS}" get secret "${WILDCARD_SECRET_NAME}" >/dev/null 2>&1; then
  echo "✅ Wildcard TLS secret '${WILDCARD_SECRET_NAME}' already exists."
else
  echo "⚠️ Creating Wildcard Certificate..."

  kubectl apply -f "${WILDCARD_CERT_MANIFEST}"

  echo "⏳ Waiting for certificate to become Ready..."
  kubectl -n "${WILDCARD_SECRET_NS}" wait \
    --for=condition=Ready certificate/"${WILDCARD_CERT_NAME}" \
    --timeout=20m
fi

echo "🎉 TLS bootstrap complete."
