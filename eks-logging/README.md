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

**Data flow:**
1. Container runtime writes logs to `/var/log/containers/*.log` on each node
2. FluentD tails these files, parses JSON/CRI format, enriches with K8s metadata
3. Logs are sent to both Elasticsearch (real-time) and S3 (long-term backup)
4. Kibana queries Elasticsearch indices for visualization and search

## Directory Structure

```
eks-logging/
├── helm-elasticsearch/              # Elasticsearch Helm chart (deployed first)
│   ├── Chart.yaml                   # Chart metadata (appVersion: 8.5.1)
│   ├── namespace.yaml               # Creates the shared "logging" namespace
│   ├── values.yaml                  # Default values (dev-friendly)
│   ├── values/
│   │   ├── dev-values.yaml          # 1 replica, no persistence, security off
│   │   ├── staging-values.yaml      # 2 replicas, 50Gi gp2, xpack on
│   │   └── prod-values.yaml         # 3 replicas, 100Gi gp2, xpack + transport SSL
│   └── templates/
│       ├── elasticsearch-configmap.yaml       # elasticsearch.yml (discovery, security)
│       ├── elasticsearch-statefulset.yaml     # StatefulSet with sysctl init, probes, anti-affinity
│       ├── elasticsearch-service.yaml         # ClusterIP on 9200/9300
│       ├── elasticsearch-service-headless.yaml # Headless service for pod discovery
│       └── elasticsearch-pdb.yaml             # PodDisruptionBudget (staging/prod)
├── helm-kibana/                     # Kibana Helm chart
│   ├── Chart.yaml                   # Chart metadata (appVersion: 8.5.1)
│   ├── namespace.yaml               # Conditional (disabled — ES creates namespace)
│   ├── values.yaml                  # Default values + ES connection settings
│   ├── values/
│   │   ├── dev-values.yaml          # 1 replica, HTTP, no TLS
│   │   ├── staging-values.yaml      # 1 replica, TLS via cert-manager
│   │   └── prod-values.yaml         # 2 replicas, TLS, PDB enabled
│   └── templates/
│       ├── kibana-configmap.yaml    # kibana.yml (ES host, security settings)
│       ├── kibana-deployment.yaml   # Deployment with probes, security context
│       ├── kibana-service.yaml      # ClusterIP on 5601
│       ├── kibana-ingress.yaml      # nginx Ingress with IP whitelist + basic auth
│       └── kibana-pdb.yaml          # PodDisruptionBudget (prod only)
├── helm-fluentd/                    # FluentD Helm chart
│   ├── Chart.yaml                   # Chart metadata (appVersion: 1.16)
│   ├── namespace.yaml               # Conditional (disabled — ES creates namespace)
│   ├── values.yaml                  # Default values + dual output config (ES + S3)
│   ├── values/
│   │   ├── dev-values.yaml          # SA fluentd-dev, dev S3 bucket
│   │   ├── staging-values.yaml      # SA fluentd-staging, larger buffers
│   │   └── prod-values.yaml         # SA fluentd-prod, 4 flush threads, system-node-critical
│   └── templates/
│       ├── fluentd-configmap.yaml         # fluent.conf (4-stage pipeline)
│       ├── fluentd-daemonset.yaml         # DaemonSet with host mounts, tolerations
│       ├── fluentd-serviceaccount.yaml    # IRSA-annotated ServiceAccount
│       ├── fluentd-clusterrole.yaml       # Read pods/namespaces for log enrichment
│       └── fluentd-clusterrolebinding.yaml # Binds ClusterRole to ServiceAccount
├── iam/
│   ├── fluentd-s3-policy.json       # IAM policy template for S3 read/write
│   └── irsa-setup.sh                # Creates IRSA role + trust policy (dev only)
├── docker/
│   └── fluentd/Dockerfile           # Custom FluentD image with ES8 + S3 plugins
├── scripts/
│   ├── deploy.sh                    # Full deployment orchestration (6 steps)
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
- ingress-nginx controller deployed on the cluster

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
# Get AWS account ID (needed for IRSA annotation and ECR image URL)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. Deploy Elasticsearch (creates the namespace — must be first)
helm upgrade --install elasticsearch-dev ./eks-logging/helm-elasticsearch \
  --namespace logging --create-namespace \
  --values ./eks-logging/helm-elasticsearch/values/dev-values.yaml \
  --wait --timeout 10m

# 2. Deploy Kibana (connects to ES at "logging-elasticsearch:9200")
helm upgrade --install kibana-dev ./eks-logging/helm-kibana \
  --namespace logging \
  --values ./eks-logging/helm-kibana/values/dev-values.yaml \
  --wait --timeout 5m

# 3. Deploy FluentD (pass AWS account ID for IRSA annotation + ECR image URL)
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

**Deploy order matters**: Elasticsearch must be deployed first — it creates the namespace and the service that Kibana and FluentD reference. Kibana and FluentD can be deployed in either order after that.

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
| TLS Ingress | No (HTTP) | Yes (letsencrypt) | Yes (letsencrypt) |
| FluentD Flush Threads | 2 | 2 | 4 |
| FluentD Priority Class | -- | -- | system-node-critical |
| S3 Bucket | eks-logs-312ubuntu-dev | eks-logs-312ubuntu-staging | eks-logs-312ubuntu-prod |
| Cluster Name | projectx_cluster_ubuntu25b | eks-cluster-staging | eks-cluster-prod |

## Cross-Chart References

The three charts are fully independent Helm releases. Cross-chart wiring uses explicit values rather than computed helpers, making it easy to grep and override per environment:

| Chart | Value Key | Default | Purpose |
|-------|-----------|---------|---------|
| helm-kibana | `elasticsearch.host` | `logging-elasticsearch` | ES service name |
| helm-kibana | `elasticsearch.port` | `9200` | ES HTTP port |
| helm-fluentd | `fluentd.output.elasticsearch.host` | `logging-elasticsearch` | ES service name |
| helm-fluentd | `fluentd.output.elasticsearch.port` | `9200` | ES HTTP port |

The ES service name is derived from `{{ .Values.namespace.name }}-elasticsearch` (defaults to `logging-elasticsearch`). Each environment values file sets the host explicitly so there are no hidden dependencies.

## FluentD Pipeline

The fluent.conf configuration implements a 4-stage label-based routing pipeline:

```
Sources (@tail)  ──▶  Filters (@KUBERNETES)  ──▶  Dispatch (@DISPATCH)  ──▶  Output (@OUTPUT)
  │                       │                           │                         │
  │ Tail container        │ Enrich with K8s           │ Prometheus              │ Dual output:
  │ log files             │ metadata (pod,            │ metrics counter         │ - Elasticsearch
  │ (JSON + CRI)          │ namespace, labels)        │                         │ - S3 (gzip)
  │                       │ + cluster_name, env       │                         │
  │                       │                           │                         │
  │                       └─ FluentD's own logs ──▶ @FLUENT_LOG ──▶ /dev/null  │
```

## Security

### Kibana Access Control

Two layers protect the Kibana dashboard:

1. **IP Whitelist** -- Configured via `kibana.ingress.whitelistSourceRange` in values. Only requests from allowed CIDRs reach Kibana through the nginx ingress controller.
2. **Basic Auth** -- Credentials stored in AWS SecretsManager at `eks/logging/kibana-credentials-<env>`. The `create-kibana-secret.sh` script pulls them (or generates defaults if the secret doesn't exist) and creates a Kubernetes secret in htpasswd format.

### FluentD S3 Access (IRSA)

FluentD uses IAM Roles for Service Accounts to write logs to S3 without static credentials:

- **Dev**: `iam/irsa-setup.sh` creates the IAM role, trust policy (referencing the cluster's OIDC provider), and attaches the S3 policy.
- **Staging/Prod**: IAM roles should be managed by IAM automation (MRP25BUBUN-6).
- The service account annotation (`eks.amazonaws.com/role-arn`) is set via `aws.accountId` passed at install time with `--set`.

### Elasticsearch Security

- **Dev**: xpack security is disabled for simplicity.
- **Staging**: xpack security enabled, transport SSL disabled.
- **Prod**: xpack security enabled with transport SSL for inter-node encryption.

## Staging/Prod Requirements

The chart code and all environment values files are ready. The following infrastructure is needed before deploying to staging/prod:

| Requirement | Status | Details |
|-------------|--------|---------|
| Staging/prod EKS clusters | Not yet | Need Terraform to create new clusters |
| S3 buckets | Not yet | `eks-logs-312ubuntu-staging`, `eks-logs-312ubuntu-prod` |
| IRSA for staging/prod | Not yet | MRP25BUBUN-6 (IAM automation) should handle this |
| Cluster names | Placeholder | Update `clusterName` in staging/prod FluentD values |
| cert-manager | Not yet | Required for TLS ingress (letsencrypt-prod issuer) |
| GHA multi-env workflow | Not yet | Current workflow only targets dev |

## Incident: S3 API Request Cost Spike ($74.51) — Root Cause Analysis

### Summary

In February 2026, AWS Cost Explorer showed a sudden spike to **$74.51/month** in S3 costs for the `eks-logs-312ubuntu-dev` bucket. The cost was not from storage — it was entirely from **S3 API request charges** (Requests-Tier1 and Requests-Tier2). CloudTrail investigation traced the issue to the FluentD S3 output plugin configuration.

### Symptoms

- **Cost Explorer** showed $74.51 total S3 cost (average monthly was $5.32), with usage type filtered to `Requests-Tier1` and `Requests-Tier2` only
- **Usage graph** showed ~200M+ S3 requests in February 2026, compared to near-zero in prior months
- All costs were in `us-east-1`, service: `S3 (Simple Storage Service)`

### Root Cause

The FluentD S3 output plugin was configured with a **sequential index-based key format**:

```
s3_object_key_format %{path}%{index}.%{file_extension}
```

This produced S3 keys like `logs/0.gz`, `logs/1.gz`, ..., `logs/19688.gz`. The `%{index}` placeholder causes `fluent-plugin-s3` to perform a **sequential HeadObject scan** — it calls `HEAD` on every key starting from 0 until it finds an unused index number. As objects accumulated, the scan grew linearly.

**CloudTrail evidence** (6 log files from a 7-minute window on 2026-02-23):

| Metric | Value |
|--------|-------|
| Total HeadObject calls (7 min) | 14,407 |
| Total PutObject calls (actual writes) | 1 |
| Read-to-write ratio | 14,407 : 1 |
| Key pattern | 100% sequential `logs/N.gz` (N = 8 to 19,688) |
| Fluentd pods scanning simultaneously | 4 (each scanning the full range independently) |
| Extrapolated monthly requests | ~41,000,000 |
| IAM role | `fluentd-s3-dev` (EKS OIDC federation) |
| Source IPs | 4 distinct EKS node IPs in us-east-1 |

All 4 FluentD DaemonSet pods independently scanned the same full index range (`logs/8.gz` through `logs/19688.gz`) on every flush cycle, because the key format had no per-pod partition. This produced **O(existing_objects * pods)** HEAD requests per write — a cost that grows worse over time as more objects exist.

### Solution

Changed the S3 output configuration in `helm-fluentd/templates/fluentd-configmap.yaml`:

| Setting | Before (broken) | After (fixed) |
|---------|-----------------|---------------|
| `s3_object_key_format` | `%{path}%{index}.%{file_extension}` | `%{path}%{time_slice}/%{uuid_flush}.%{file_extension}` |
| `check_bucket` | not set (defaults to true) | `false` |
| Buffer mode | `flush_mode interval` / `flush_interval 60s` | `timekey 3600` / `timekey_wait 10m` |
| Buffer tag | `<buffer>` | `<buffer time>` |

**Why this fixes the issue:**
- `%{uuid_flush}` generates a globally unique key per flush — no existence check needed, zero HeadObject calls
- `%{time_slice}` partitions logs into hourly directories (e.g., `logs/2026022314/`) — better for lifecycle policies and Athena queries
- `check_bucket false` skips the startup bucket existence HEAD request
- `<buffer time>` with `timekey` enables time-based chunking required by `%{time_slice}`

**S3 path structure change:**
```
Before: logs/0.gz, logs/1.gz, ..., logs/19688.gz    (flat, sequential)
After:  logs/2026022314/a1b2c3d4.gz                  (hourly partitions, UUID keys)
```

**Estimated cost impact:**
| | Before | After |
|--|--------|-------|
| HeadObject calls per write | ~19,000 (growing) | 0 |
| Monthly API requests | ~41,000,000 | ~43,200 (1 PUT per flush, hourly per pod) |
| Monthly S3 API cost | $74.51 | < $0.05 |

### Lessons Learned

1. **Never use `%{index}` in `fluent-plugin-s3`** — it has O(n) HEAD cost per write that grows with object count
2. **S3 API request costs can exceed storage costs** — even a dev bucket with minimal data can generate $70+/month from request volume alone
3. **Monitor CloudTrail data events** — `HeadObject` storms are invisible in standard metrics but obvious in CloudTrail
4. **Time-based keys with UUIDs are the correct pattern** for high-throughput log shipping to S3

---

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
| ES pods stuck in Init | `vm.max_map_count` sysctl init needs privileged | Check `sysctlInit.enabled: true` in values |
| Kibana ingress rejected (duplicate host) | Old release with same ingress host still deployed | `helm uninstall <old-release> -n logging` |
| FluentD pods CrashLoopBackOff | ECR image not found or IRSA not configured | Check ECR repo exists; run `iam/irsa-setup.sh` |
| FluentD pods Pending | Node capacity full (too many pods) | Wait for Karpenter to scale nodes |
| ES 400 errors in FluentD logs | Pre-formatted `@timestamp` in JSON container logs | Known minor issue with ES 8.5.1, non-blocking |
| Kibana FATAL on startup | `xpack.security.enabled: false` set in Kibana config | Remove that key — Kibana 8.x does not recognize it |
| ingress-nginx webhook blocking install | Controller pods are down | `kubectl delete validatingwebhookconfiguration ingress-nginx-admission` |
| `%!s(int64=...)` in IRSA annotation | `aws.accountId` rendered as int, not string | Template uses `toString` — pass as `--set aws.accountId=<value>` |
| High S3 API request costs ($70+/month) | `s3_object_key_format` uses `%{index}` — causes O(n) HeadObject scan | Use `%{time_slice}/%{uuid_flush}` instead. See [Incident: S3 API Request Cost Spike](#incident-s3-api-request-cost-spike-7451--root-cause-analysis) |

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

1. Setup IRSA for FluentD S3 access
2. Build and push custom FluentD image to ECR
3. `helm upgrade --install elasticsearch-<env>` (creates namespace)
4. `helm upgrade --install kibana-<env>`
5. `helm upgrade --install fluentd-<env>` (with `--set aws.accountId`)
6. Create Kibana auth secret
7. Verify deployment (pods, services, ingress)
8. Run integration tests (`test-logging.sh`)

## Dependencies

| Dependency | Details |
|------------|---------|
| S3 Bucket | `eks-logs-312ubuntu-<env>` — must exist before FluentD can write logs |
| ECR Repository | `fluentd-es-s3` — created automatically by deploy script/workflow if missing |
| SecretsManager (optional) | `eks/logging/kibana-credentials-<env>` — script generates defaults if missing |
| DNS | CNAME for `kibana-ubuntu-<env>.312ubuntu.com` pointing to the NLB hostname |
| ingress-nginx | Must be deployed before Kibana ingress can be created |
| EBS CSI Driver | Required for persistent ES volumes in staging/prod (gp2 StorageClass) |
| IAM for staging/prod | Managed by IAM automation (MRP25BUBUN-6), not by irsa-setup.sh |
