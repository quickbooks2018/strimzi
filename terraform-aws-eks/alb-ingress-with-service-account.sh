#!/bin/bash
set -x

export CLUSTER_NAME="cloudgeeks-eks-dev"
export AWS_DEFAULT_REGION="us-east-1"
export MY_AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region $AWS_DEFAULT_REGION | awk '{print $5}' | grep -i vpc)

export AWS_ACCOUNT_ID="602401143452" # aws ecr account
# https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html

# Download IAM Policy
## Download latest
curl -o iam_policy_latest.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

# Create IAM Policy using policy downloaded
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy_latest.json

eksctl create iamserviceaccount \
    --region ${AWS_DEFAULT_REGION} \
    --name aws-load-balancer-controller \
    --namespace kube-system \
    --cluster ${CLUSTER_NAME} \
    --attach-policy-arn arn:aws:iam::${MY_AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
    --override-existing-serviceaccounts \
    --approve

# Get IAM Service Account
eksctl get iamserviceaccount --cluster ${CLUSTER_NAME}

# Describe Service Account aws-load-balancer-controller
kubectl describe sa aws-load-balancer-controller -n kube-system

# Add the eks-charts repository.
helm repo add eks https://aws.github.io/eks-charts

# Update your local repo to make sure that you have the most recent charts.
helm repo update

# Install the AWS Load Balancer Controller.
## Template
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=${AWS_DEFAULT_REGION} \
  --set vpcId=${VPC_ID} \
  --set image.repository=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/amazon/aws-load-balancer-controller


# END
