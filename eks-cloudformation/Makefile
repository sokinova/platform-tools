name = eks-dev
region = us-east-1
aws := aws --region $(region)
account = $(shell aws sts get-caller-identity --query "Account" --output text)
role = EKS_ReadOnlyAccess_Role
include cluster_config

SpotPrice = 0.0464
NodeGroupName = $(name)-workers
WorkersStackName = $(name)-workers
ami = $(shell aws ssm get-parameter --name /aws/service/eks/optimized-ami/$(version)/amazon-linux-2023/x86_64/standard/recommended/image_id --region $(region) --query "Parameter.Value" --output text)

default: help

# Lists the available targets
help:
	@make -qp | awk -F':' '/^[a-z0-9][^$$#\/\t=]*:([^=]|$$)/ {split($$1,A,/ /);for(i in A)print A[i]}' | sort

cluster: prereq secret-generator iam sshkeys eks workers oidc

prereq:
	eksctl version || (echo "Please install eksctl" && exit 1;)
	kubectl > /dev/null || (echo "Please install kubectl" && exit 1);

oidc:
	@$(eval role_arn := $(shell $(aws) cloudformation describe-stacks --query "Stacks[?StackName=='$(name)'][].Outputs[?OutputKey=='EBSDriverRoleArn'].OutputValue" --output text))
	kubectl annotate serviceaccount ebs-csi-controller-sa -n kube-system eks.amazonaws.com/role-arn=$(role_arn) --overwrite
	eksctl utils associate-iam-oidc-provider --cluster $(name) --approve --region $(region)
	kubectl rollout restart deployment ebs-csi-controller -n kube-system


secret-generator:
	@$(aws) cloudformation create-stack \
		--capabilities CAPABILITY_IAM \
		--stack-name cfn-secret-provider \
		--template-body file://cloudformation/cfn-resource-provider.yaml || echo "will skip creation then"
	@$(aws) cloudformation wait stack-create-complete  --stack-name cfn-secret-provider

delete-secret-generator:
	@$(aws) cloudformation delete-stack --stack-name cfn-secret-provider

sshkeys:
	@$(aws) cloudformation create-stack --stack-name eks-node-secrets --template-body file://cloudformation/ec2-sshkeypair.yaml ||  echo "will skip creation then"

delete-sshkeys:
	@$(aws) cloudformation delete-stack --stack-name eks-node-secrets

get-private-key:
	$(aws) ssm get-parameter --name /eks-node-secrets/private-key --with-decryption --output text --query 'Parameter.Value' > ~/.ssh/eks-node-secrets.pem
	@chmod 600 ~/.ssh/eks-node-secrets.pem

eks:
	$(aws) cloudformation create-stack --stack-name $(name) \
		--template-body file://cloudformation/eks.yaml \
		--capabilities CAPABILITY_IAM \
		--parameter ParameterKey=VpcBlock,ParameterValue=$(VpcBlock) \
			ParameterKey=ClusterVersion,ParameterValue=$(version) \
			ParameterKey=Subnet01Block,ParameterValue=$(Subnet01Block) \
			ParameterKey=Subnet02Block,ParameterValue=$(Subnet02Block) \
			ParameterKey=Subnet03Block,ParameterValue=$(Subnet03Block) \
			ParameterKey=Subnet01Az,ParameterValue=$(Subnet01Az) \
			ParameterKey=Subnet02Az,ParameterValue=$(Subnet02Az) \
			ParameterKey=Subnet03Az,ParameterValue=$(Subnet03Az)  || echo "will skip creation then"
	$(aws) cloudformation wait stack-create-complete --stack-name $(name)
	@echo "waiting for the cluster to start, can take 10 minutes..."
	$(aws) eks describe-cluster --name $(name) --query cluster.status

delete-eks:
	@$(aws) cloudformation delete-stack --stack-name $(name)

iam:
	@$(aws) cloudformation create-stack --stack-name $(name)-iam \
		--template-body file://cloudformation/iam.yaml \
		--capabilities CAPABILITY_NAMED_IAM \
		--parameters ParameterKey=NodeStack,ParameterValue=$(WorkersStackName) || echo "will skip creation then"
	@$(aws) cloudformation wait stack-create-complete --stack-name $(name)-iam

# Configures and deploys the worker nodes
replacements="\
s|IAM_ROLE|$(role)|g;\
s|ACCOUNT_NUMBER|$(account)|g;\
s|NODE_INSTANCE_ROLE|$(NodeInstanceRole)|g;\
"

update-kubeconfig:
	aws eks --region $(region) update-kubeconfig --name $(name)

workers: update-kubeconfig
	@$(eval securitygroups := $(shell $(aws) cloudformation describe-stacks \
		--stack-name $(name) \
		--query 'Stacks[0].Outputs[?OutputKey==`SecurityGroups`].OutputValue' \
		--output text | sed 's/,/\\\\,/g'))
	@$(eval subnetids := $(shell $(aws) cloudformation describe-stacks \
		--stack-name $(name) \
		--query 'Stacks[0].Outputs[?OutputKey==`SubnetIds`].OutputValue' \
		--output text | sed 's/,/\\\\,/g'))
	@$(eval vpcid := $(shell $(aws) cloudformation describe-stacks \
		--stack-name $(name) \
		--query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
		--output text))
	@$(eval nodeInstanceProfile :=  $(shell $(aws) cloudformation describe-stacks \
	--stack-name $(name)-iam \
	--query 'Stacks[0].Outputs[?OutputKey==`NodeInstanceProfile`].OutputValue' --output text | rev | cut -f 1 -d '/' | rev))
	$(eval NodeInstanceRole := $(shell $(aws) cloudformation describe-stacks \
	--stack-name $(name)-iam \
	--query 'Stacks[0].Outputs[?OutputKey==`NodeInstanceRole`].OutputValue' \
	--output text))
	@$(aws) cloudformation create-stack \
		--capabilities CAPABILITY_IAM \
		--stack-name $(WorkersStackName) \
		--template-body file://cloudformation/amazon-eks-nodegroup.yaml \
		--parameter ParameterKey=ClusterControlPlaneSecurityGroup,ParameterValue=$(securitygroups) \
			ParameterKey=ClusterName,ParameterValue=$(name) \
			ParameterKey=KeyName,ParameterValue=eks-node-secrets-keypair \
			ParameterKey=NodeAutoScalingGroupDesiredCapacity,ParameterValue=$(asgDesired) \
			ParameterKey=NodeAutoScalingGroupMaxSize,ParameterValue=$(asgMax) \
			ParameterKey=NodeAutoScalingGroupMinSize,ParameterValue=$(asgMin) \
			ParameterKey=NodeGroupName,ParameterValue=$(NodeGroupName) \
			ParameterKey=NodeImageId,ParameterValue=$(ami) \
			ParameterKey=NodeInstanceType,ParameterValue=$(instanceType) \
			ParameterKey=NodeInstanceProfile,ParameterValue=$(nodeInstanceProfile) \
			ParameterKey=NodeVolumeSize,ParameterValue=$(volumeSize) \
			ParameterKey=SpotPrice,ParameterValue=$(SpotPrice) \
			ParameterKey=Subnets,ParameterValue=$(subnetids) \
			ParameterKey=VpcId,ParameterValue=$(vpcid) || echo "will skip creation then"
	@$(aws) cloudformation wait stack-create-complete  --stack-name $(WorkersStackName)
	@cat kubernetes/aws-auth-cm.yaml | sed $(replacements) | kubectl apply -f -

delete-workers:
	@$(aws) cloudformation delete-stack --stack-name $(WorkersStackName)
	$(aws) cloudformation wait stack-delete-complete --stack-name $(WorkersStackName)

