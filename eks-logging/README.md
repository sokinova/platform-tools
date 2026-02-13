# EKS Logging with EFK Stack (Elasticsearch, FluentD, Kibana)

## Overview

Centralized logging solution for Amazon EKS using the EFK stack. Collects container logs from every node via FluentD, stores them in Elasticsearch for real-time search, visualizes through Kibana, and backs up to S3 for long-term retention.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    EKS Cluster (logging namespace)           │
│                                                              │
│  ┌─────────────┐    ┌────────────────┐    ┌──────────────┐  │
│  │   FluentD    │───▶│ Elasticsearch  │◀───│   Kibana     │  │
│  │  (DaemonSet) │    │ (StatefulSet)  │    │ (Deployment) │  │
│  └──────┬───────┘    └────────────────┘    └──────┬───────┘  │
│         │                                         │          │
│         │  ┌──────────┐              ┌────────────┴───────┐  │
│         └─▶│ S3 Bucket│              │ Ingress (nginx)    │  │
│            │ (backup) │              │ + IP whitelist      │  │
│            └──────────┘              │ + basic auth        │  │
│                                      └────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
eks-logging/
├── chart/                           # Custom Helm chart
│   ├── Chart.yaml
│   ├── values.yaml                  # Default values (dev-friendly)
│   ├── values/
│   │   ├── dev-values.yaml
│   │   ├── staging-values.yaml
│   │   └── prod-values.yaml
│   └── templates/
│       ├── _helpers.tpl             # Reusable template helpers
│       ├── NOTES.txt                # Post-install instructions
│       ├── namespace.yaml
│       ├── elasticsearch-*.yaml     # ConfigMap, StatefulSet, Service, Headless, PDB
│       ├── kibana-*.yaml            # ConfigMap, Deployment, Service, Ingress, PDB
│       └── fluentd-*.yaml           # ServiceAccount, ClusterRole, Binding, ConfigMap, DaemonSet
├── docker/                          # Custom FluentD image (if present)
├── scripts/
│   ├── deploy.sh                    # Full deployment orchestration
│   ├── create-kibana-secret.sh      # Kibana auth from SecretsManager
│   └── test-logging.sh              # Integration tests (12 checks)
├── namespace.yaml                   # Standalone namespace manifest
└── README.md
```

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate credentials
- `kubectl` connected to EKS cluster
- Helm 3.x installed
- S3 bucket created: `eks-logs-312ubuntu-<env>`

### Deploy (single command)

```bash
./eks-logging/scripts/deploy.sh dev
```

This script handles:
1. IRSA setup for FluentD S3 access (dev only)
2. Custom FluentD Docker image build/push to ECR
3. Helm chart deployment with environment-specific values
4. Kibana auth secret creation
5. Deployment verification

### Manual Deployment

```bash
# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Deploy the chart
helm upgrade --install efk-dev ./eks-logging/chart \
  --namespace logging --create-namespace \
  --values ./eks-logging/chart/values/dev-values.yaml \
  --set aws.accountId=${AWS_ACCOUNT_ID} \
  --wait --timeout 15m

# Create Kibana auth secret
./eks-logging/scripts/create-kibana-secret.sh dev

# Verify
kubectl get pods -n logging
./eks-logging/scripts/test-logging.sh dev
```

## Environment Configuration

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| ES Replicas | 1 | 2 | 3 |
| ES Memory | 1Gi | 2Gi | 4Gi |
| Persistence | No (emptyDir) | 50Gi gp2 | 100Gi gp2 |
| Security | Off | On | On |
| Anti-affinity | None | Soft | Hard |
| PDB | No | Yes | Yes |
| TLS | No | Yes | Yes |
| S3 Bucket | eks-logs-312ubuntu-dev | eks-logs-312ubuntu-staging | eks-logs-312ubuntu-prod |

## Security

### Kibana Access Control

1. **IP Whitelist** — Only requests from whitelisted IPs reach Kibana (configured via `kibana.ingress.whitelistSourceRange`)
2. **Basic Auth** — Username/password stored in AWS SecretsManager (`eks/logging/kibana-credentials-<env>`)

### FluentD S3 Access (IRSA)

FluentD uses IAM Roles for Service Accounts to write logs to S3. The deploy script creates the IRSA role for dev. Staging/prod should use IAM automation.

## Troubleshooting

```bash
# Check pod status
kubectl get pods -n logging

# Elasticsearch health
kubectl exec -n logging efk-dev-elasticsearch-0 -- curl -s localhost:9200/_cluster/health | python3 -m json.tool

# Kibana logs
kubectl logs -n logging -l app=kibana

# FluentD logs
kubectl logs -n logging -l app.kubernetes.io/name=fluentd --tail=50

# Check ingress
kubectl get ingress -n logging
```

## Cleanup

```bash
helm uninstall efk-dev -n logging
kubectl delete namespace logging
```

## Dependencies

- **S3 Bucket**: Create `eks-logs-312ubuntu-<env>` before deployment
- **SecretsManager** (optional): `eks/logging/kibana-credentials-<env>` — script generates defaults if missing
- **DNS**: Create CNAME record for `kibana-ubuntu-<env>.312ubuntu.com` pointing to NLB hostname
- **IAM for staging/prod**: Depends on IAM automation (separate ticket)
