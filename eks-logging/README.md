# EKS Logging with EFK Stack (Elasticsearch, FluentD, Kibana)

## Overview

This module deploys a complete logging solution for EKS clusters using the EFK stack:

- **Elasticsearch**: Log storage and search engine
- **FluentD**: Log collector (DaemonSet on all nodes)
- **Kibana**: Log visualization and dashboards

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           EKS Cluster                                     │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                        logging namespace                             │ │
│  │                                                                      │ │
│  │  ┌──────────────┐   ┌───────────────┐   ┌────────────────────────┐ │ │
│  │  │   FluentD    │──▶│ Elasticsearch │◀──│        Kibana          │ │ │
│  │  │  (DaemonSet) │   │   (StatefulSet)│   │     (Deployment)       │ │ │
│  │  └──────────────┘   └───────────────┘   └────────────────────────┘ │ │
│  │         │                                          │                │ │
│  │         │                                          │                │ │
│  │         ▼                                          ▼                │ │
│  │  ┌──────────────┐                         ┌────────────────────┐   │ │
│  │  │     S3       │                         │  Ingress (nginx)   │   │ │
│  │  │  (backup)    │                         │  + Basic Auth      │   │ │
│  │  └──────────────┘                         │  + IP Whitelist    │   │ │
│  │                                           └────────────────────┘   │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │
│  │   Node 1        │  │   Node 2        │  │   Node N        │          │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │          │
│  │ │  FluentD    │ │  │ │  FluentD    │ │  │ │  FluentD    │ │          │
│  │ │  (pod)      │ │  │ │  (pod)      │ │  │ │  (pod)      │ │          │
│  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │          │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Why EFK over ELK?

| Feature | EFK (FluentD) | ELK (Logstash) |
|---------|---------------|----------------|
| Resource usage | Lower memory footprint | Higher memory requirements |
| Cloud-native | Built for Kubernetes | Requires more configuration |
| Plugin ecosystem | 500+ plugins | 200+ plugins |
| Configuration | Declarative, simple | More complex pipelines |
| Buffer management | Built-in file buffering | Requires explicit config |

FluentD was chosen for its:
- Native Kubernetes integration
- Lower resource consumption
- Built-in S3 output plugin
- CNCF graduated project status

## Directory Structure

```
eks-logging/
├── README.md                          # This file
├── namespace.yaml                     # logging namespace
├── helm/
│   ├── elasticsearch/
│   │   ├── values-dev.yaml           # Single node, 1Gi
│   │   ├── values-staging.yaml       # 2 nodes, 2Gi
│   │   └── values-prod.yaml          # 3 nodes, 4Gi
│   ├── kibana/
│   │   ├── values-dev.yaml
│   │   ├── values-staging.yaml
│   │   └── values-prod.yaml
│   └── fluentd/
│       ├── values-dev.yaml           # ES + S3 dual output
│       ├── values-staging.yaml
│       └── values-prod.yaml
├── manifests/
│   ├── kibana-ingress-dev.yaml       # Ingress with IP whitelist
│   ├── kibana-ingress-staging.yaml
│   ├── kibana-ingress-prod.yaml
│   └── kibana-auth-secret.yaml       # Basic auth template
└── scripts/
    ├── deploy.sh                      # Full deployment script
    ├── create-kibana-secret.sh       # Auth secret setup
    └── test-logging.sh               # Verification script
```

## Prerequisites

1. **EKS Cluster** - Running and accessible via kubectl
2. **Helm 3** - Installed locally
3. **AWS CLI** - Configured with appropriate credentials
4. **ingress-nginx** - Already deployed (see `/ingress-nginx`)

### Connect to Cluster

```bash
# Login to AWS SSO: https://312school.awsapps.com/start/
# Get credentials from ubuntu-dev → Access keys → Option 1
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
export AWS_REGION=us-east-1

# Verify and update kubeconfig
aws sts get-caller-identity
aws eks update-kubeconfig --name temp-eks-cluster --region us-east-1
kubectl get pods -A
```

## Quick Start

### Deploy to Dev

```bash
./eks-logging/scripts/deploy.sh dev
```

This will:
1. Create the `logging` namespace
2. Add Helm repositories
3. Deploy Elasticsearch
4. Deploy Kibana
5. Create auth secret and Ingress
6. Deploy FluentD

### Verify Deployment

```bash
./eks-logging/scripts/test-logging.sh dev
```

## Manual Deployment

### Step 1: Create Namespace

```bash
kubectl apply -f eks-logging/namespace.yaml
```

### Step 2: Add Helm Repos

```bash
helm repo add elastic https://helm.elastic.co
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update
```

### Step 3: Deploy Elasticsearch

```bash
helm upgrade --install elasticsearch-dev elastic/elasticsearch \
  --namespace logging \
  --values eks-logging/helm/elasticsearch/values-dev.yaml \
  --wait --timeout 10m
```

### Step 4: Deploy Kibana

```bash
helm upgrade --install kibana-dev elastic/kibana \
  --namespace logging \
  --values eks-logging/helm/kibana/values-dev.yaml \
  --wait --timeout 5m
```

### Step 5: Setup Kibana Access

```bash
# Create auth secret
./eks-logging/scripts/create-kibana-secret.sh dev

# Apply ingress
kubectl apply -f eks-logging/manifests/kibana-ingress-dev.yaml
```

### Step 6: Deploy FluentD

```bash
# Replace AWS_ACCOUNT_ID in values file
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" \
  eks-logging/helm/fluentd/values-dev.yaml > /tmp/fluentd-values.yaml

helm upgrade --install fluentd-dev fluent/fluentd \
  --namespace logging \
  --values /tmp/fluentd-values.yaml \
  --wait --timeout 5m
```

## S3 Backup Configuration

FluentD is configured for dual output:
1. **Elasticsearch** - Real-time search and visualization
2. **S3** - Long-term backup and compliance

### IAM Dependency

**Note:** For FluentD to write logs to S3, an IAM role with IRSA (IAM Roles for Service Accounts) must be provisioned. This is handled separately by the IAM automation team (see MRP25BUBUN-6).

The FluentD ServiceAccount requires an IAM role with the following permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::eks-logs-312ubuntu-*/logs/*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::eks-logs-312ubuntu-*"
    }
  ]
}
```

Until the IAM role is provisioned:
- **Elasticsearch output works** - Logs flow to Elasticsearch normally
- **S3 output fails silently** - FluentD buffers logs and retries

### S3 Bucket

| Environment | Bucket Name | Lifecycle |
|-------------|-------------|-----------|
| dev | eks-logs-312ubuntu-dev | 30d → IA, 60d → Glacier |
| staging | eks-logs-312ubuntu-staging | 30d → IA, 90d → Glacier |
| prod | eks-logs-312ubuntu-prod | 30d → IA, 365d → Glacier |

### Log Path Format

```
s3://eks-logs-312ubuntu-dev/logs/YYYY/MM/DD/
```

## Access Kibana

### URLs

| Environment | URL |
|-------------|-----|
| dev | https://kibana-ubuntu-dev.312ubuntu.com |
| staging | https://kibana-staging.312ubuntu.com |
| prod | https://kibana-prod.312ubuntu.com |

### Authentication

Kibana uses basic authentication. Credentials are stored in AWS SecretsManager:
- Secret: `eks/logging/kibana-credentials-{env}`

To retrieve credentials:
```bash
aws secretsmanager get-secret-value \
  --secret-id eks/logging/kibana-credentials-dev \
  --query SecretString --output text
```

### IP Whitelist

Access is restricted by IP. Current whitelist (dev):
- `73.45.178.26/32`

To update, modify the ingress annotation:
```yaml
nginx.ingress.kubernetes.io/whitelist-source-range: "IP1/32,IP2/32"
```

## Environment Configuration

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| ES Nodes | 1 | 2 | 3 |
| ES Memory | 1Gi | 2Gi | 4Gi |
| ES Storage | 10Gi | 50Gi | 100Gi |
| Kibana Replicas | 1 | 1 | 2 |
| FluentD Memory | 256Mi | 512Mi | 1Gi |

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n logging
kubectl describe pod <pod-name> -n logging
kubectl logs <pod-name> -n logging
```

### Elasticsearch Issues

```bash
# Check cluster health
kubectl exec -n logging elasticsearch-dev-master-0 -- \
  curl -s http://localhost:9200/_cluster/health | jq

# Check indices
kubectl exec -n logging elasticsearch-dev-master-0 -- \
  curl -s http://localhost:9200/_cat/indices
```

### FluentD Issues

```bash
# Check FluentD logs
kubectl logs -n logging -l app.kubernetes.io/name=fluentd --tail=100

# Verify S3 access
kubectl exec -n logging <fluentd-pod> -- \
  aws s3 ls s3://eks-logs-312ubuntu-dev/
```

### Ingress Issues

```bash
# Check ingress status
kubectl get ingress -n logging
kubectl describe ingress kibana-dev-ingress -n logging

# Test from whitelisted IP
curl -u admin:password https://kibana-ubuntu-dev.312ubuntu.com
```

## Cleanup

```bash
# Delete all components
helm uninstall fluentd-dev -n logging
helm uninstall kibana-dev -n logging
helm uninstall elasticsearch-dev -n logging
kubectl delete -f eks-logging/manifests/kibana-ingress-dev.yaml
kubectl delete secret kibana-basic-auth -n logging
kubectl delete namespace logging
```

## Resources

- [Elasticsearch Helm Chart](https://github.com/elastic/helm-charts/tree/main/elasticsearch)
- [Kibana Helm Chart](https://github.com/elastic/helm-charts/tree/main/kibana)
- [FluentD Helm Chart](https://github.com/fluent/helm-charts/tree/main/charts/fluentd)
- [FluentD S3 Plugin](https://docs.fluentd.org/output/s3)
