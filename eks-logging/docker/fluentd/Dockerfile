# ============================================================
# Custom FluentD Docker Image for EFK Stack
# ============================================================
# Extends the official FluentD Kubernetes DaemonSet image with the S3 output plugin.
# The base image already includes the Elasticsearch 8 output plugin.
#
# Why a custom image:
#   The base image only ships with the ES plugin. We need dual output (ES + S3),
#   so we add fluent-plugin-s3 at build time.
#
# Why bundle exec instead of fluent-gem install:
#   The base image uses Bundler to manage gems. Gems installed via "fluent-gem install"
#   go to the system path and are NOT visible to FluentD at runtime (which runs
#   under "bundle exec"). So we add the gem to the Gemfile and run "bundle install".
#
# Build:
#   docker build -t fluentd-es-s3:v1.16-es8-s3 -f eks-logging/docker/fluentd/Dockerfile .
#
# Push to ECR:
#   aws ecr get-login-password | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
#   docker tag fluentd-es-s3:v1.16-es8-s3 <account>.dkr.ecr.us-east-1.amazonaws.com/fluentd-es-s3:v1.16-es8-s3
#   docker push <account>.dkr.ecr.us-east-1.amazonaws.com/fluentd-es-s3:v1.16-es8-s3
# ============================================================

# Base image: FluentD 1.16 with Elasticsearch 8 plugin pre-installed
FROM fluent/fluentd-kubernetes-daemonset:v1.16-debian-elasticsearch8-1

# Switch to root to install build dependencies
USER root

# Install fluent-plugin-s3 into the Bundler-managed gem path
# build-essential is needed for native C extensions required by aws-sdk-core (bigdecimal gem)
# After installation, build tools are removed to keep the image small
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential && \
    cd /fluentd && \
    echo "gem 'fluent-plugin-s3', '~> 1.8.0'" >> Gemfile && \
    bundle install && \
    apt-get purge -y build-essential && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Switch back to the non-root "fluent" user for runtime security
USER fluent
