# Kubernetes User Roles

## Overview and Architecture
This repository defines Kubernetes user roles and access control using **RBAC (Role-Based Access Control)**.  

- RBAC roles and permissions are managed via **Helm charts**.  
- Environment-specific configurations are provided using `values-dev.yaml` and `values-prod.yaml`.  
- **AWS EKS Access Entries** are used to allow IAM roles to access the cluster securely. 
**Directory structure:**
k8s-user-roles/
├── README.md
└── ReadAccessClusterRole/
├── Chart.yaml
├── templates/
│ ├── RBAC.yaml
│ └── clusterRole.yaml
├── values-dev.yaml
└── values-prod.yaml

## Issues
**Challenges encountered:**

- Configuring IAM roles with **EKS Access Entries**.
- Managing environment-specific RBAC for dev vs prod.  
- Ensuring Helm charts apply RBAC resources in the correct order.  

**Solutions implemented:**

- Environment-specific Helm values files (`values-dev.yaml`, `values-prod.yaml`).  
- Helm templates to generate RBAC resources dynamically.  
- Ensure the cluster allows **API or API_AND_CONFIG_MAP authentication mode** and **AWS CLI is installed**, otherwise AWS EKS access entries will not work. 


## How to Run/Execute in CI/CD pipeline
**Install helm**
      # Install Helm
      - name: Install Helm
        uses: azure/setup-helm@v3
        with:
          version: 'v3.13.0'
**Install AWS CLI**
      #Install AWS CLI
      - name: Ensure AWS CLI is installed
        run: |
            if ! command -v aws &> /dev/null
            then
              echo "AWS CLI not found. Installing..."
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip -q awscliv2.zip
              sudo ./aws/install
            else
              echo "AWS CLI already installed"
            fi
**Deploy ClusterRole and RBAC**
      - name: Deploy Cluster role and RBAC
        run: |
            helm upgrade --install read-access k8s-user-roles/ReadAccessClusterRole \
            -f k8s-user-roles/ReadAccessClusterRole/values-${ENVIRONMENT_STAGE}.yaml \
            --namespace helm-system \
            --create-namespace  
**Create aws eks access entry**
      # Create aws eks access entry
      - name: Ensure EKS Access Entry
        run: |
            set -e  # exit on any error

            ROLE_ARN="arn:aws:iam::383585068161:role/DeveloperProdAccessRole-ubuntu25b"

            if ! aws eks describe-access-entry \
                --cluster-name "$CLUSTER_NAME" \
                --principal-arn "$ROLE_ARN" >/dev/null 2>&1; then
              echo "Access entry not found. Creating..."
              aws eks create-access-entry \
                --cluster-name "$CLUSTER_NAME" \
                --principal-arn "$ROLE_ARN" \
                --type STANDARD \
                --kubernetes-groups dev-team \
                --username DeveloperProdAccessRole
            else
              echo "Access entry exists. Updating..."
              aws eks update-access-entry \
                --cluster-name "$CLUSTER_NAME" \
                --principal-arn "$ROLE_ARN" \
                --kubernetes-groups dev-team \
                --username DeveloperProdAccessRole
            fi
**Verify Access Entry**
      # Verify Access Entry 
      - name: Verify Access Entry
        run: |
          aws eks list-access-entries \
            --cluster-name $CLUSTER_NAME

## Resources
https://kubernetes.io/docs/reference/access-authn-authz/rbac/ (ClusterRole and RBAC manifests)
https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry (aws_eks_access_entry creation)

## Additional Information
Create templates for ClusterRole and RBAC and deploy thru helm. Make sure API or API_AND_CONFIG_MAP authentication mode is set to cluster. Then create access_entry. If cluster's authentication mode is set to CONFIG_MAP, aws access entry will not work.
