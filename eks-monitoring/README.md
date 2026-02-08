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

### Grafana
- created templates to deploy Grafana
- Grafana tested in dev environment
- Deployed in our EKS cluster
- created login and password 
- configured ingress 
- implemented tls certificate for secure connection to https://grafana-ubuntu-dev.312ubuntu.com/login
- added annottion 
- aws
### Helm
- created the helm chart structure

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

 AWS Secret Manager 
aws secretsmanager create-secret \
  --name "eks-monitoring/grafana-admin" \
  --secret-string '{"admin-user":"admin","admin-password":"ChangeMe-Strong123!"}'



## Resources
  - https://prometheus.io/docs/
  - https://prometheus.io/docs/prometheus/latest/configuration/template_examples/
  - https://github.com/prometheus/prometheus
  - https://github.com/prometheus/node_exporter
  - https://github.com/kubernetes/kube-state-metrics


## Additional Information
[Extra information or personal notes]