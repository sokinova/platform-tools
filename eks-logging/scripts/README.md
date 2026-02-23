# EFK Scripts

## Why These Exist

These scripts are called by the GHA workflow (`.github/workflows/deploy-platform-tools.yaml`) during deployment. They are not optional — removing them will break the CI/CD pipeline.

## Files

### `create-kibana-secret.sh`

Creates the Kubernetes secret used for Kibana basic auth (username/password prompt on the ingress).

**How it works:**
1. Checks AWS SecretsManager for existing credentials (`eks/logging/kibana-credentials-<env>`)
2. If not found, generates random credentials and stores them in SecretsManager
3. Formats credentials as htpasswd (Apache-style hash)
4. Creates/updates the `kibana-basic-auth` K8s secret in the logging namespace

**Called by:** GHA workflow step "Create Kibana auth secret"

### `test-logging.sh`

Runs 8 integration checks after deployment to verify the EFK stack is healthy:

1. `logging` namespace exists
2. Elasticsearch pods running + cluster health (green/yellow)
3. Kibana pods running
4. FluentD pods running on all nodes (DaemonSet coverage)
5. Kibana ingress configured + load balancer provisioned
6. `kibana-basic-auth` K8s secret exists
7. Elasticsearch contains log indices (logs are flowing)
8. S3 bucket accessible + log files present (retries up to 90s for flush delay)

**Called by:** GHA workflow step "Run EFK integration tests"

## Removed

`deploy.sh` was previously in this directory as a manual deployment orchestration script. It was removed because the GHA workflow handles all deployment steps, and the README documents the manual `helm upgrade` commands for anyone who needs them.
