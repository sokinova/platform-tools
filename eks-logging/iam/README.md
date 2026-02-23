# IAM for FluentD S3 Access (IRSA)

## Why This Exists

FluentD writes log backups to S3. Instead of storing static AWS access keys in the cluster, we use **IRSA (IAM Roles for Service Accounts)** — a secure, keyless authentication method where the Kubernetes ServiceAccount assumes an IAM role via the cluster's OIDC provider.

## Files

### `fluentd-s3-policy.json`

IAM policy granting FluentD the minimum permissions needed for S3:
- `s3:ListBucket` / `s3:GetBucketLocation` on the bucket
- `s3:PutObject` / `s3:GetObject` / `s3:DeleteObject` on the `logs/*` prefix

### `irsa-setup.sh`

Creates the IAM role and trust policy for **dev** environments. It:
1. Queries the cluster's OIDC provider URL
2. Creates an IAM role (`fluentd-s3-<env>`) with a trust policy scoped to the specific ServiceAccount
3. Attaches the S3 policy from `fluentd-s3-policy.json`

**Usage:** Called automatically by the GHA workflow. Can also be run manually:
```bash
CLUSTER_NAME=projectx_cluster_ubuntu25b ./irsa-setup.sh dev
```

## Staging/Prod

For staging and prod, IRSA roles should be managed by IAM automation (MRP25BUBUN-6), not by this script. The script prints a warning if run for non-dev environments.

## If S3 Output Is Removed

If the team decides S3 backup is no longer needed, this entire `iam/` directory can be deleted along with the IRSA setup step in the GHA workflow.
