#!/bin/bash
# EFK Stack Verification Script
# Tests all components of the logging stack

set -e

# Configuration
ENVIRONMENT=${1:-dev}
NAMESPACE="logging"
S3_BUCKET="eks-logs-312ubuntu-${ENVIRONMENT}"
AWS_REGION=${AWS_REGION:-us-east-1}

echo "=========================================="
echo "EFK Stack Verification - ${ENVIRONMENT}"
echo "=========================================="
echo ""

PASSED=0
FAILED=0

# Helper function for test results
check_result() {
  if [ $1 -eq 0 ]; then
    echo "  [PASS] $2"
    PASSED=$((PASSED + 1))
  else
    echo "  [FAIL] $2"
    FAILED=$((FAILED + 1))
  fi
}

# Test 1: Check namespace exists
echo "[1/8] Checking namespace..."
kubectl get namespace ${NAMESPACE} >/dev/null 2>&1
check_result $? "Namespace '${NAMESPACE}' exists"
echo ""

# Test 2: Check Elasticsearch pods
echo "[2/8] Checking Elasticsearch..."
ES_PODS=$(kubectl get pods -n ${NAMESPACE} -l app=elasticsearch-master -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
if [[ "${ES_PODS}" == *"Running"* ]]; then
  check_result 0 "Elasticsearch pods running"
else
  check_result 1 "Elasticsearch pods running"
fi

# Check Elasticsearch cluster health
ES_POD=$(kubectl get pods -n ${NAMESPACE} -l app=elasticsearch-master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "${ES_POD}" ]; then
  HEALTH=$(kubectl exec -n ${NAMESPACE} ${ES_POD} -- curl -s http://localhost:9200/_cluster/health 2>/dev/null | jq -r '.status' 2>/dev/null)
  if [[ "${HEALTH}" == "green" ]] || [[ "${HEALTH}" == "yellow" ]]; then
    check_result 0 "Elasticsearch cluster health: ${HEALTH}"
  else
    check_result 1 "Elasticsearch cluster health: ${HEALTH:-unknown}"
  fi
else
  check_result 1 "Elasticsearch cluster health check"
fi
echo ""

# Test 3: Check Kibana pods
echo "[3/8] Checking Kibana..."
KIBANA_PODS=$(kubectl get pods -n ${NAMESPACE} -l app=kibana -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
if [[ "${KIBANA_PODS}" == *"Running"* ]]; then
  check_result 0 "Kibana pods running"
else
  check_result 1 "Kibana pods running"
fi
echo ""

# Test 4: Check FluentD pods
echo "[4/8] Checking FluentD..."
FLUENTD_PODS=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=fluentd -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
if [[ "${FLUENTD_PODS}" == *"Running"* ]]; then
  check_result 0 "FluentD pods running"

  # Count FluentD pods vs nodes
  FLUENTD_COUNT=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=fluentd --no-headers 2>/dev/null | wc -l)
  NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  if [ "${FLUENTD_COUNT}" -eq "${NODE_COUNT}" ]; then
    check_result 0 "FluentD DaemonSet running on all ${NODE_COUNT} nodes"
  else
    check_result 1 "FluentD DaemonSet: ${FLUENTD_COUNT}/${NODE_COUNT} nodes"
  fi
else
  check_result 1 "FluentD pods running"
fi
echo ""

# Test 5: Check Kibana Ingress
echo "[5/8] Checking Kibana Ingress..."
INGRESS=$(kubectl get ingress -n ${NAMESPACE} kibana-${ENVIRONMENT}-ingress -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
if [ -n "${INGRESS}" ]; then
  check_result 0 "Kibana Ingress configured: ${INGRESS}"

  # Check if LB is provisioned
  LB=$(kubectl get ingress -n ${NAMESPACE} kibana-${ENVIRONMENT}-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [ -n "${LB}" ]; then
    check_result 0 "Load balancer provisioned: ${LB}"
  else
    check_result 1 "Load balancer provisioned (pending)"
  fi
else
  check_result 1 "Kibana Ingress configured"
fi
echo ""

# Test 6: Check auth secret
echo "[6/8] Checking Kibana auth secret..."
kubectl get secret kibana-basic-auth -n ${NAMESPACE} >/dev/null 2>&1
check_result $? "Kibana auth secret exists"
echo ""

# Test 7: Check Elasticsearch indices
echo "[7/8] Checking Elasticsearch indices..."
if [ -n "${ES_POD}" ]; then
  INDICES=$(kubectl exec -n ${NAMESPACE} ${ES_POD} -- curl -s http://localhost:9200/_cat/indices 2>/dev/null | grep -c "kubernetes" || echo "0")
  if [ "${INDICES}" -gt 0 ]; then
    check_result 0 "Kubernetes log indices found: ${INDICES}"
  else
    check_result 1 "Kubernetes log indices found (logs may not be flowing yet)"
  fi
else
  check_result 1 "Elasticsearch indices check"
fi
echo ""

# Test 8: Check S3 bucket
echo "[8/8] Checking S3 bucket..."
if aws s3 ls "s3://${S3_BUCKET}" --region ${AWS_REGION} >/dev/null 2>&1; then
  check_result 0 "S3 bucket '${S3_BUCKET}' accessible"

  # Check for log files
  LOG_COUNT=$(aws s3 ls "s3://${S3_BUCKET}/logs/" --recursive --region ${AWS_REGION} 2>/dev/null | wc -l)
  if [ "${LOG_COUNT}" -gt 0 ]; then
    check_result 0 "Log files found in S3: ${LOG_COUNT}"
  else
    check_result 1 "Log files in S3 (logs may not be flushed yet)"
  fi
else
  check_result 1 "S3 bucket '${S3_BUCKET}' accessible"
fi
echo ""

# Summary
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo "  Passed: ${PASSED}"
echo "  Failed: ${FAILED}"
echo ""

if [ ${FAILED} -eq 0 ]; then
  echo "All tests passed!"
  exit 0
else
  echo "Some tests failed. Check the output above for details."
  exit 1
fi
