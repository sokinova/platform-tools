# EKS Logging - EFK Stack (Elasticsearch, FluentD, Kibana)

## Overview

Centralized logging solution for Amazon EKS using the EFK stack, deployed as three independent Helm charts. FluentD runs as a DaemonSet on every node collecting container logs, sends them to Elasticsearch for real-time search and to S3 for long-term backup, and Kibana provides the visualization layer behind an IP-whitelisted, basic-auth-protected ingress.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     EKS Cluster (logging namespace)              │
│                                                                  │
│  ┌──────────────┐    ┌─────────────────┐    ┌───────────────┐   │
│  │   FluentD     │───▶│  Elasticsearch  │◀───│    Kibana     │   │
│  │  (DaemonSet)  │    │  (StatefulSet)  │    │  (Deployment) │   │
│  └──────┬────────┘    └─────────────────┘    └──────┬────────┘   │
│         │                                           │            │
│         │  ┌───────────┐               ┌────────────┴────────┐   │
│         └─▶│ S3 Bucket │               │  Ingress (nginx)    │   │
│            │  (backup)  │               │  + IP whitelist     │   │
│            └───────────┘               │  + basic auth       │   │
│                                         └────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
eks-logging/
├── helm-elasticsearch/              # Elasticsearch Helm chart
│   ├── Chart.yaml
│   ├── namespace.yaml               # Creates the logging namespace
│   ├── values.yaml                  # Default values (dev-friendly)
│   ├── values/
│   │   ├── dev-values.yaml
│   │   ├── staging-values.yaml
│   │   └── prod-values.yaml
│   └── templates/
│       ├── elasticsearch-configmap.yaml
│       ├── elasticsearch-statefulset.yaml
│       ├── elasticsearch-service.yaml
│       ├── elasticsearch-service-headless.yaml
│       └── elasticsearch-pdb.yaml
├── helm-kibana/                     # Kibana Helm chart
│   ├── Chart.yaml
│   ├── namespace.yaml
│   ├── values.yaml
│   ├── values/
│   │   ├── dev-values.yaml
│   │   ├── staging-values.yaml
│   │   └── prod-values.yaml
│   └── templates/
│       ├── kibana-configmap.yaml
│       ├── kibana-deployment.yaml
│       ├── kibana-service.yaml
│       ├── kibana-ingress.yaml
│       └── kibana-pdb.yaml
├── helm-fluentd/                    # FluentD Helm chart
│   ├── Chart.yaml
│   ├── namespace.yaml
│   ├── values.yaml
│   ├── values/
│   │   ├── dev-values.yaml
│   │   ├── staging-values.yaml
│   │   └── prod-values.yaml
│   └── templates/
│       ├── fluentd-configmap.yaml
│       ├── fluentd-daemonset.yaml
│       ├── fluentd-serviceaccount.yaml
│       ├── fluentd-clusterrole.yaml
│       └── fluentd-clusterrolebinding.yaml
├── iam/
│   ├── fluentd-s3-policy.json       # IAM policy for S3 access
│   └── irsa-setup.sh                # Creates IRSA role + trust policy
├── docker/
│   └── fluentd/Dockerfile           # Custom FluentD image with ES8 + S3 plugins
├── scripts/
│   ├── deploy.sh                    # Full deployment orchestration
│   ├── create-kibana-secret.sh      # Kibana basic-auth from SecretsManager
│   └── test-logging.sh              # Integration tests (8 checks)
└── README.md
```

## Quick Start

### Prerequisites

- AWS CLI v2 configured with appropriate credentials
- `kubectl` connected to the target EKS cluster
- Helm 3.x installed
- Docker (for building the custom FluentD image)
- S3 bucket created: `eks-logs-312ubuntu-<env>`

### Automated Deployment

```bash
./eks-logging/scripts/deploy.sh dev
```

The script handles the full lifecycle:
1. IRSA setup for FluentD S3 access (dev only; staging/prod uses IAM automation)
2. Custom FluentD Docker image build and push to ECR
3. Elasticsearch chart deployment (creates the `logging` namespace)
4. Kibana chart deployment
5. FluentD chart deployment
6. Kibana basic-auth secret creation and verification

### Manual Deployment

```bash
# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. Deploy Elasticsearch (creates the namespace)
helm upgrade --install elasticsearch-dev ./eks-logging/helm-elasticsearch \
  --namespace logging --create-namespace \
  --values ./eks-logging/helm-elasticsearch/values/dev-values.yaml \
  --wait --timeout 10m

# 2. Deploy Kibana
helm upgrade --install kibana-dev ./eks-logging/helm-kibana \
  --namespace logging \
  --values ./eks-logging/helm-kibana/values/dev-values.yaml \
  --wait --timeout 5m

# 3. Deploy FluentD (requires AWS account ID for IRSA annotation)
helm upgrade --install fluentd-dev ./eks-logging/helm-fluentd \
  --namespace logging \
  --values ./eks-logging/helm-fluentd/values/dev-values.yaml \
  --set aws.accountId=${AWS_ACCOUNT_ID} \
  --wait --timeout 5m

# 4. Create Kibana basic-auth secret
./eks-logging/scripts/create-kibana-secret.sh dev

# 5. Verify
kubectl get pods -n logging
./eks-logging/scripts/test-logging.sh dev
```

**Deploy order matters**: Elasticsearch must be deployed first (it creates the namespace and the service that Kibana and FluentD reference). Kibana and FluentD can be deployed in either order after that.

## Environment Configuration

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| ES Replicas | 1 | 2 | 3 |
| ES Memory (request/limit) | 1Gi / 2Gi | 2Gi / 4Gi | 4Gi / 8Gi |
| ES Java Heap | 512m | 1g | 2g |
| Persistence | No (emptyDir) | 50Gi gp2 | 100Gi gp2 |
| Security (xpack) | Off | On | On + transport SSL |
| Anti-affinity | None | Soft | Hard |
| PDB | No | Yes (maxUnavailable: 1) | Yes (maxUnavailable: 1) |
| Kibana Replicas | 1 | 1 | 2 |
| TLS Ingress | No | Yes | Yes |
| FluentD Priority Class | -- | -- | system-node-critical |
| ES Flush Threads | 2 | 2 | 4 |
| S3 Bucket | eks-logs-312ubuntu-dev | eks-logs-312ubuntu-staging | eks-logs-312ubuntu-prod |
| Cluster Name | temp-eks-cluster | eks-cluster-staging | eks-cluster-prod |

## Cross-Chart References

The three charts are fully independent. Cross-chart wiring uses explicit values rather than computed helpers, making it easy to grep and override per environment:

| Chart | Value | Default |
|-------|-------|---------|
| helm-kibana | `elasticsearch.host` | `logging-elasticsearch` |
| helm-kibana | `elasticsearch.port` | `9200` |
| helm-fluentd | `fluentd.output.elasticsearch.host` | `logging-elasticsearch` |
| helm-fluentd | `fluentd.output.elasticsearch.port` | `9200` |

The ES service name is derived from `{{ .Values.namespace.name }}-elasticsearch` (defaults to `logging-elasticsearch`). Each env-values file sets the host explicitly so there are no hidden dependencies.

## Security

### Kibana Access Control

Two layers protect the Kibana dashboard:

1. **IP Whitelist** -- Configured via `kibana.ingress.whitelistSourceRange` in values. Only requests from allowed CIDRs reach Kibana.
2. **Basic Auth** -- Credentials stored in AWS SecretsManager at `eks/logging/kibana-credentials-<env>`. The `create-kibana-secret.sh` script pulls them (or generates defaults if the secret doesn't exist) and creates a Kubernetes secret.

### FluentD S3 Access (IRSA)

FluentD uses IAM Roles for Service Accounts to write logs to S3 without static credentials:

- **Dev**: `iam/irsa-setup.sh` creates the IAM role, trust policy (referencing the cluster's OIDC provider), and attaches the S3 policy.
- **Staging/Prod**: IAM roles should be managed by IAM automation (separate ticket).
- The service account annotation (`eks.amazonaws.com/role-arn`) is set via `aws.accountId` passed at install time.

### Elasticsearch Security

- **Dev**: xpack security is disabled for simplicity.
- **Staging**: xpack security enabled, transport SSL disabled.
- **Prod**: xpack security enabled with transport SSL for inter-node encryption.

## Troubleshooting

```bash
# Pod status
kubectl get pods -n logging

# Elasticsearch cluster health
kubectl exec -n logging logging-elasticsearch-0 -- \
  curl -s localhost:9200/_cluster/health | python3 -m json.tool

# Elasticsearch indices (check if logs are flowing)
kubectl exec -n logging logging-elasticsearch-0 -- \
  curl -s localhost:9200/_cat/indices?v

# Kibana logs
kubectl logs -n logging -l app=kibana --tail=50

# FluentD logs (check for ES connection errors or S3 write failures)
kubectl logs -n logging -l app=fluentd --tail=50

# Ingress status
kubectl get ingress -n logging

# Helm release status
helm list -n logging
```

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| Kibana ingress rejected (duplicate host) | Old unified `efk-dev` release still deployed | `helm uninstall efk-dev -n logging` |
| FluentD pods in CrashLoopBackOff | ECR image not found or IRSA not configured | Check ECR repo exists; run `iam/irsa-setup.sh` |
| ES 400 errors in FluentD logs | Pre-formatted `@timestamp` in JSON container logs | Known minor issue with ES 8.5.1, non-blocking |
| Kibana FATAL on startup | `xpack.security.enabled: false` set explicitly | Remove that key entirely (Kibana 8.x doesn't recognize it) |
| ingress-nginx admission webhook blocking install | Controller pods are down | `kubectl delete validatingwebhookconfiguration ingress-nginx-admission` |

## Cleanup

Uninstall in reverse order (FluentD first, Elasticsearch last):

```bash
helm uninstall fluentd-dev -n logging
helm uninstall kibana-dev -n logging
helm uninstall elasticsearch-dev -n logging
kubectl delete namespace logging
```

## CI/CD

The GitHub Actions workflow (`.github/workflows/deploy-platform-tools.yaml`) deploys all three charts sequentially on push to `feature/**` or `main`:

1. Setup IRSA for FluentD
2. Build and push custom FluentD image to ECR
3. Cleanup old unified EFK release (one-time migration)
4. `helm upgrade --install elasticsearch-<env>`
5. `helm upgrade --install kibana-<env>`
6. `helm upgrade --install fluentd-<env>`
7. Create Kibana auth secret
8. Verify deployment
9. Run integration tests (`test-logging.sh`)

## Dependencies

| Dependency | Details |
|------------|---------|
| S3 Bucket | `eks-logs-312ubuntu-<env>` -- must exist before FluentD can write logs |
| ECR Repository | `fluentd-es-s3` -- created automatically by deploy script if missing |
| SecretsManager (optional) | `eks/logging/kibana-credentials-<env>` -- script generates defaults if missing |
| DNS | CNAME for `kibana-ubuntu-<env>.312ubuntu.com` pointing to NLB hostname |
| ingress-nginx | Must be deployed before Kibana ingress can be created |
| IAM for staging/prod | Depends on IAM automation (separate ticket) |
