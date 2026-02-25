# External-DNS Automated Test

This folder contains **temporary Kubernetes resources** used by the GitHub Actions pipeline to **verify external-dns end-to-end**.

**Goal**
If external-dns is working correctly, an annotated Ingress should automatically create a DNS record and traffic should resolve successfully.

**These resources are created during CI, validated, and deleted automatically.**

---

## What Gets Created

### Deployment
A minimal `nginx` Deployment used as a stable HTTP backend.

**Why it exists**
- Provides a predictable endpoint for testing
- Fast startup, zero configuration
- No app logic — just HTTP 200s

**Key points**
- Single replica
- Exposes port `80`

---

### Service
A ClusterIP Service that exposes the Deployment internally.

**Why it exists**
- Ingress requires a Service backend
- Keeps networking realistic (Ingress > Service > Pod)

**Key points**
- Selects pods via `app: dns-test`
- Forwards traffic to port `80`

---

### Ingress
The core of the test.  
This Ingress is annotated so `external-dns` can detect it and create a DNS record in Route 53.

**Why it exists**
- Triggers external-dns
- Proves annotation-based DNS management works
- Simulates real production usage

**Important annotation**
external-dns.alpha.kubernetes.io/hostname: dns-test.312ubuntu.com 


How the test works (logic):
1. Deployment creates Pods labeled app=dns-test
2. Service selects those Pods and exposes port 80
3. Ingress routes traffic to the Service and defines the hostname
4. external-dns detects the annotation and creates the DNS record
5. CI validates DNS + HTTP, then deletes the test resources

- **Pass** = `nslookup` resolves + `curl` returns success  
- **Fail**  = DNS never appears or HTTP doesn’t route