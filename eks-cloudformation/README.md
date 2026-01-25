# 312-eks-common

## Contents
  This repository contains the following files:
  - Cloudformation templates in the [cloudformation](https://github.com/312-bc/312-eks-common/tree/test-branch/cloudformation) folder.
  - Kubernetes manifests in the [kubernetes](https://github.com/312-bc/312-eks-common/tree/test-branch/kubernetes) folder.
  - [Makefile](https://github.com/312-bc/312-eks-common/blob/test-branch/Makefile) to create cluster with commands.
  - [cluster_config](https://github.com/312-bc/312-eks-common/blob/test-branch/cluster_config) with variables to customize your cluster.

## Usage
### Prerequisites
   - Install the AWS CLI:
  ~~~bash
  pip install awscli
  ~~~
   - Install kubectl:
  ~~~bash
  brew install kubernetes-cli
  ~~~  
   - Install eksctl
     https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html

## Run
  1. Edit parameters on run:
      - `version`: to set eks cluster version.
      - `role`: to set iam role for eks access.
  2. Run:
      ~~~bash
      make cluster version=1.34 role=EXAMPLE_IAM_ROLE
      make cluster version=1.34 role="arn:aws:iam::036692858685:role/aws-reserved/sso.amazonaws.com/us-east-2/AWSReservedSSO_Administrator_0238c8388aaa3bbe"
      ~~~
