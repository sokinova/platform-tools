# Custom FluentD image with Elasticsearch + S3 plugins
# Base: Official FluentD Kubernetes DaemonSet image with Elasticsearch 8 plugin
# Added: fluent-plugin-s3 for dual output (ES + S3 backup)
#
# Build:
#   docker build -t fluentd-es-s3:v1.16-es8-s3 -f eks-logging/docker/fluentd/Dockerfile .
#
# Push to ECR:
#   aws ecr get-login-password | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
#   docker tag fluentd-es-s3:v1.16-es8-s3 <account>.dkr.ecr.us-east-1.amazonaws.com/fluentd-es-s3:v1.16-es8-s3
#   docker push <account>.dkr.ecr.us-east-1.amazonaws.com/fluentd-es-s3:v1.16-es8-s3

FROM fluent/fluentd-kubernetes-daemonset:v1.16-debian-elasticsearch8-1

# Install fluent-plugin-s3 into the bundler-managed gem path
# The base image uses Gemfile + bundle exec, so fluent-gem install
# (which goes to system path) is NOT visible to FluentD at runtime.
# Build tools are needed for native extensions (bigdecimal via aws-sdk-core).
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential && \
    cd /fluentd && \
    echo "gem 'fluent-plugin-s3', '~> 1.8.0'" >> Gemfile && \
    bundle install && \
    apt-get purge -y build-essential && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*
USER fluent
