# External-DNS Automated Test

This folder contains **temporary Kubernetes resources** used by the GitHub Actions pipeline to **verify external-dns functionality end-to-end**.

The goal:
> If external-dns is working correctly, a DNS record should be created automatically from an annotated Ingress and traffic should resolve successfully.

 **These resources are created during CI, validated, and deleted automatically**.

---

## What Gets Created

### Deployment (`test-deploy.yaml`)
A minimal `nginx` Deployment used as a stable HTTP backend.

**Why it exists**
- Provides a predictable endpoint for testing
- Fast startup, zero configuration
- No app logic — just HTTP 200s

**Key points**
- Single replica
- Runs in the `external-dns` namespace
- Exposes port `80`

---

### Service (`test-deploy.yaml`)
A ClusterIP Service that exposes the Deployment internally.

**Why it exists**
- Ingress requires a Service backend
- Keeps networking realistic (Ingress > Service > Pod)

**Key points**
- Selects pods via `app: dns-test`
- Forwards traffic to port `80`

---

### Ingress (`test-ingress.yaml`)
The core of the test.  
This Ingress is annotated so `external-dns` can detect it and create a DNS record in Route 53.

**Why it exists**
- Triggers external-dns
- Proves annotation-based DNS management works
- Simulates real production usage

**Important annotation**
```yaml
external-dns.alpha.kubernetes.io/hostname: dns-test.312ubuntu.com


How the test works (logic):
1) Deployment creates Pods labeled app=dns-test
2) Service selects those Pods (selector app=dns-test) and exposes port 80
3) Ingress routes traffic to the Service and defines the hostname
4) external-dns detects the annotation and creates the DNS record