terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
   #   version = "4.7.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = "~> 1.0"
}


### Backend ###
# S3
###############

terraform {
  backend "s3" {
    bucket         = "cloudgeeksca-terraform"
    key            = "env/dev/cloudgeeksca-dev.tfstate"
    region         = "us-east-1"
   # dynamodb_table = "cloudgeeks-dev-terraform-backend-state-lock"
  }
}

#  Error: configmaps "aws-auth" already exists
#  Solution: kubectl delete configmap aws-auth -n kube-system

#########
# Eks Vpc
#########
module "eks_vpc" {
  source  = "registry.terraform.io/terraform-aws-modules/vpc/aws"
  version = "3.11.0"

  name            = var.cluster_name

  cidr            = "10.60.0.0/16"
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.60.0.0/23", "10.60.2.0/23", "10.60.4.0/23"]
  public_subnets  = ["10.60.100.0/23", "10.60.102.0/24", "10.60.104.0/24"]


  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false

  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = false
  create_database_nat_gateway_route      = true

  enable_dns_hostnames = true
  enable_dns_support   = true

# https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "karpenter.sh/discovery"                    = var.cluster_name
    "kubernetes.io/role/internal-elb"           = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"       = "1"
  }


}



#############
# Eks Cluster
#############
module "eks" {
  source  = "registry.terraform.io/terraform-aws-modules/eks/aws"
  version = "17.24.0"

  cluster_version           = "1.21"
  cluster_name              = "cloudgeeks-eks-dev"
  vpc_id                    = module.eks_vpc.vpc_id
  subnets                   = module.eks_vpc.private_subnets
  workers_role_name         = "iam-eks-workers-role"
  create_eks                = true
  manage_aws_auth           = false
  write_kubeconfig          = false
  kubeconfig_output_path    = "/root/.kube/config" # touch /root/.kube/config   # for terraform HELM provider, we neeed this + #  Error: configmaps "aws-auth" already exists 
  kubeconfig_name           = "config"                                                                                         #  Solution: kubectl delete configmap aws-auth -n kube-system
  enable_irsa               = true                 # oidc
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/17.21.0/submodules/node_groups
  node_groups = {
    cloudgeeks-eks-workers = {
      create_launch_template = true
      name                   = "cloudgeeks-eks-workers"  # Eks Workers Node Groups Name
      instance_types         = ["t3a.medium"]
      capacity_type          = "ON_DEMAND"
      desired_capacity       = 5
      max_capacity           = 5
      min_capacity           = 5
      disk_type              = "gp3"
      disk_size              = 30
      ebs_optimized          = true
      disk_encrypted         = true
      key_name               = "terraform-cloudgeeks"
      enable_monitoring      = true

      additional_tags = {
        "Name"                     = "eks-worker"                            # Tags for Cluster Worker Nodes
        "karpenter.sh/discovery"   = var.cluster_name
      }

    }
  }

      tags = {
    # Tag node group resources for Karpenter auto-discovery
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    "karpenter.sh/discovery" = var.cluster_name
  }

}
