# External DNS

## Overview and Architecture
External DNS is used to automatically create and manage DNS records in AWS Route53 based on Kubernetes Ingress resources.

In this setup:

- External DNS runs as a Kubernetes Deployment in an EKS cluster
- It watches **Ingress resources only**
- DNS records are created **only when an Ingress has a DNS annotation**
- AWS access is handled using **IRSA (IAM Roles for Service Accounts)**
- No AWS credentials are stored inside Kubernetes

### Architecture Flow

1. An Ingress is created with a DNS hostname annotation  
2. External DNS detects the annotated Ingress  
3. External DNS assumes an IAM role via IRSA  
4. DNS records are created or updated in AWS Route53  
5. DNS points to the Kubernetes Ingress Load Balancer  

TXT records are used to track ownership and prevent conflicts between environments.

---

## Issues

### Pods were not created (Deployment stuck at 0 replicas)

**Cause:**  
The Deployment referenced a ServiceAccount named `external-dns`, but the ServiceAccount did not exist.
Helm was configured with `serviceAccount.create: false`, so Helm did not create the ServiceAccount.

**Resolution:**  
- Set ServiceAccount 'Create' to 'true'
- Annotated it with the correct IRSA role ARN
- Reinstalled the helm
  - Can be optianally provisioned via kubctl in the terminal

### Multiple Helm revisions during deployment

**Cause:**
Each helm upgrade creates a new Helm revision (expected behavior).

**Resolution:**
No action required. Helm revisions allow rollback and auditing.

### Multiple Helm revisions during deployment

**Cause:**  
Each `helm upgrade` creates a new Helm revision (expected Helm behavior).

**Resolution:**  
No action required. Helm revisions allow rollback and change tracking.

---

## How to Run/Execute
[Guidelines on how to implement and use External DNS]

### Deploy External DNS using Helm in the dev
```bash

helm upgrade --install external-dns external-dns/external-dns-helm \
  -n external-dns \
  -f external-dns/external-dns-helm/values.yaml \

```

### Verify External DNS is running
```bash
kubectl -n external-dns get pods
kubectl -n external-dns logs deploy/external-dns
```

### Create a test ingress
1. use the ingress-test.yaml in the external dns module of platform-tools-25b-ubuntu repo
2. kubectl -n external-dns apply -f ingress-test.yaml > it will create the ingress with annotation:
annotations:
```bash
  external-dns.alpha.kubernetes.io/hostname: external-dns-test.312ubuntu.com
```

### Verify DNS record creation

**Check logs**

```bash
kubectl -n external-dns logs deploy/external-dns
```

**Check Route53**
```bash
aws route53 list-resource-record-sets --hosted-zone-id <HOSTED_ZONE_ID>
```

---

## Resources
- External DNS GitHub
https://github.com/kubernetes-sigs/external-dns

External DNS Helm Chart
https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns

AWS IRSA Documentation
https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

AWS Route53 Documentation
https://docs.aws.amazon.com/route53/

---

## Additional Information
[Other relevant information or tips]

- TXT records are used to prevent cross-environment DNS ownership conflicts even when sharing the same Route53 hosted zone
- Each environment should use a unique txt-owner-id
- DNS changes may take time to propagate
- Always verify DNS directly in Route53 when troubleshooting
- Deployments should be automated via CI/CD (GitHub Actions)