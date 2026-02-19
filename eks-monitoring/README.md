# EKS Monitoring with Prometheus and Grafana stack
The EKS monitoring setup is built on open-source tools, using Prometheus for metrics collection and Grafana for visualization.

## Overview and Architecture
More cost-effective solution by adopting open-source tools like Prometheus, Grafana.
 This decision aligns with the company’s initiative to optimize expenses while maintaining efficient monitoring capabilities.

The goal is to make Prometheus and Grafana fully integrated into the AWS EKS cluster for monitoring, with configurations managed in the Platform Tools Repository.


## What is implemented:
- configured manifest files to setup Prometheus as a data source.
- created templates to deploy Prometheus
- Prometheus server tested to be deployed to the EKS cluster
- tested to be deployed via a **custom Helm chart** (no public charts)
- created templates to deploy Grafana
- Grafana tested in dev environment
- deployed in our EKS cluster
- created login and password
- configured ingress 
- implemented tls certificate for secure connection to https://grafana-ubuntu-dev.312ubuntu.com/login
- created the helm chart structure


### Prometheus 
In this EKS monitoring setup, Prometheus collects metrics from kube-state-metrics, node-exporter, the Kubernetes API server, and application workloads that expose metrics. These metrics include CPU usage, memory usage, pod status, restart counts, request rates, and error rates. This provides a complete view of both infrastructure and application performance. 

### Grafana
Grafana is an open-source platform for data visualization, monitoring, and analysis. It allows users to query, visualize, and alert on metrics, logs, and traces from diverse data sources like Prometheus. Users access Grafana securely via HTTPS through the Ingress. 

In this project, Grafana is configured to use Prometheus as its primary data source. Grafana queries Prometheus using PromQL and transforms the results into interactive dashboards. This allows users to monitor cluster health, track application performance, analyze trends over time, and detect issues visually.

Grafana is exposed securely through an Ingress controller with TLS enabled, ensuring encrypted HTTPS access. Authentication is configured to protect access to monitoring dashboards. This ensures that monitoring data remains secure while still being accessible via a public endpoint.

### Security

- Grafana exposed via HTTPS (TLS enabled)
- Ingress configured with hostname:
  grafana-ubuntu-dev.312ubuntu.com
- Authentication enabled (login & password)
- Custom Helm charts used for better configuration control
- Designed for environment separation (dev / staging / production)
- AWS Secrets Manager integration

## How to Run/Execute
deploy Prometheus: 
```bash
helm upgrade --install eks-monitoring ./helm \
  -n eks-monitoring-dev --create-namespace \
  -f ./helm/values/dev-values.yaml
```

deploy Grafana:
```bash
helm upgrade --install eks-monitoring-grafana ./helm-grafana \
  -n eks-monitoring-dev --create-namespace \
  -f ./helm-grafana/values/dev-values.yaml
```

validate and check running pods:
```bash
kubectl get pods -n eks-monitoring
```
to get acsses to prometheus ui:
```bash
kubectl -n eks-monitoring-dev port-forward svc/eks-monitoring-prometheus 9090:9090
```
then open http://localhost:9090

to get acsses to grafana :
``` bash
https://grafana-ubuntu-dev.312ubuntu.com/
```


## Resources
  - https://prometheus.io/docs/
  - https://prometheus.io/docs/prometheus/latest/configuration/template_examples/
  - https://github.com/prometheus/prometheus
  - https://github.com/prometheus/node_exporter
  - https://github.com/kubernetes/kube-state-metrics