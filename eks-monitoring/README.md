# EKS Monitoring with Prometheus and Grafana stack
The EKS monitoring setup is built on open-source tools, using Prometheus for metrics collection and Grafana for visualization.

## Overview and Architecture
More cost-effective solution by adopting open-source tools like Prometheus, Grafana.
 This decision aligns with the company’s initiative to optimize expenses while maintaining efficient monitoring capabilities.

The goal is to make Prometheus and Grafana fully integrated into the AWS EKS cluster for monitoring, with configurations managed in the Platform Tools Repository.

Grafana and alerting will be added in later stages once the Prometheus foundation is validated.

## What is implemented

### Prometheus
- created templates to deploy Prometheus
- Prometheus server tested to be deployed to the EKS cluster
- tested to be deployed via a **custom Helm chart** (no public charts)

### Helm
- created the helm chart structure

## How to Run/Execute
deploy Prometheus: 
```bash
helm upgrade --install eks-monitoring ./helm \
  -n eks-monitoring-dev --create-namespace \
  -f ./helm/values/dev-values.yaml
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

## Resources
  - https://prometheus.io/docs/
  - https://prometheus.io/docs/prometheus/latest/configuration/template_examples/
  - https://github.com/prometheus/prometheus
  - https://github.com/prometheus/node_exporter
  - https://github.com/kubernetes/kube-state-metrics


## Additional Information
[Extra information or personal notes]