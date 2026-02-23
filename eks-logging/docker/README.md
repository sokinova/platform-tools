# Custom FluentD Docker Image

## Why This Exists

The official FluentD Kubernetes DaemonSet image (`fluent/fluentd-kubernetes-daemonset:v1.16-debian-elasticsearch8-1`) only includes the Elasticsearch output plugin. Our EFK stack sends logs to **both** Elasticsearch (real-time search) and **S3** (long-term backup), so we need the `fluent-plugin-s3` gem added.

This Dockerfile extends the base image with that single plugin.

## Why Not Just `fluent-gem install`?

The base image uses **Bundler** to manage gems. Gems installed via `fluent-gem install` go to the system path and are **not visible** to FluentD at runtime (which runs under `bundle exec`). So we add the gem to the Gemfile and run `bundle install` instead.

## Build and Push

The GHA workflow handles this automatically. For manual builds:

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/fluentd-es-s3"

docker build -t "${ECR_REPO}:v1.16-es8-s3" -f eks-logging/docker/fluentd/Dockerfile .
docker push "${ECR_REPO}:v1.16-es8-s3"
```

## If S3 Output Is Removed

If the team decides S3 backup is no longer needed, this entire `docker/` directory can be deleted. The FluentD DaemonSet would then use the base image directly (no ECR, no custom build).
