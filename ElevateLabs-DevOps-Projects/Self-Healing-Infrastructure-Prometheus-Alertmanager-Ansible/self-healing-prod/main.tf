###############################################################################
# Self-Healing Infrastructure — Terraform AWS Production
# Provisions: VPC, EKS Cluster, Node Groups, MSK, RDS, ALB, Monitoring
###############################################################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "self-healing-infra/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "self-healing-infra"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "platform-sre"
      CostCenter  = "infra-001"
    }
  }
}

# ─── Data Sources ──────────────────────────────────────────────────────────────
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

# ─── Local Values ─────────────────────────────────────────────────────────────
locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"
  azs          = slice(data.aws_availability_zones.available.names, 0, 3)
  account_id   = data.aws_caller_identity.current.account_id

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Cluster     = local.cluster_name
  }
}

###############################################################################
# MODULE: VPC
###############################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.4.0"

  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs
  intra_subnets   = var.intra_subnet_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment == "dev" ? true : false
  enable_vpn_gateway     = false
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # EKS required subnet tags
  public_subnet_tags = {
    "kubernetes.io/role/elb"                       = 1
    "kubernetes.io/cluster/${local.cluster_name}"  = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"              = 1
    "kubernetes.io/cluster/${local.cluster_name}"  = "shared"
  }

  tags = local.tags
}

###############################################################################
# MODULE: EKS CLUSTER
###############################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.2.1"

  cluster_name    = local.cluster_name
  cluster_version = var.eks_cluster_version

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.allowed_cidr_blocks

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        replicaCount = 2
        resources = {
          limits   = { cpu = "0.25", memory = "256M" }
          requests = { cpu = "0.25", memory = "256M" }
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent              = true
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
      configuration_values = jsonencode({
        env = {
          ENABLE_POD_ENI                    = "true"
          ENABLE_PREFIX_DELEGATION          = "true"
          POD_SECURITY_GROUP_ENFORCING_MODE = "standard"
        }
      })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # Managed Node Groups
  eks_managed_node_groups = {
    # System node group — for critical cluster components
    system = {
      name           = "system"
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      disk_size      = 50

      labels = {
        role = "system"
      }
      taints = [{
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }

    # Application node group — for workloads
    application = {
      name           = "application"
      instance_types = ["m5.xlarge", "m5a.xlarge"]
      min_size       = var.app_node_min
      max_size       = var.app_node_max
      desired_size   = var.app_node_desired
      disk_size      = 100
      capacity_type  = "ON_DEMAND"

      labels = {
        role = "application"
        team = "platform"
      }

      update_config = {
        max_unavailable_percentage = 33
      }
    }

    # Spot node group — for batch/non-critical workloads
    spot = {
      name           = "spot"
      instance_types = ["m5.large", "m5a.large", "m4.large"]
      min_size       = 0
      max_size       = 10
      desired_size   = 2
      disk_size      = 50
      capacity_type  = "SPOT"

      labels = {
        role          = "spot"
        "spot/enabled" = "true"
      }
      taints = [{
        key    = "spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }

    # Monitoring node group — dedicated for Prometheus/Grafana
    monitoring = {
      name           = "monitoring"
      instance_types = ["r5.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      disk_size      = 200

      labels = {
        role = "monitoring"
      }
    }
  }

  # Cluster access entries
  enable_cluster_creator_admin_permissions = true

  tags = local.tags
}

###############################################################################
# IRSA Roles (IAM Roles for Service Accounts)
###############################################################################
module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.33.0"

  role_name             = "${local.cluster_name}-vpc-cni"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.33.0"

  role_name             = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "load_balancer_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.33.0"

  role_name                              = "${local.cluster_name}-aws-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

###############################################################################
# StorageClass — GP3
###############################################################################
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    iops      = "3000"
    throughput = "125"
  }
}

###############################################################################
# HELM: AWS Load Balancer Controller
###############################################################################
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.2"

  set {
    name  = "clusterName"
    value = local.cluster_name
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.load_balancer_controller_irsa.iam_role_arn
  }
  set {
    name  = "replicaCount"
    value = "2"
  }

  depends_on = [module.eks]
}

###############################################################################
# HELM: Cluster Autoscaler
###############################################################################
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.34.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = local.cluster_name
  }
  set {
    name  = "awsRegion"
    value = var.aws_region
  }
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler.arn
  }

  depends_on = [module.eks]
}

###############################################################################
# HELM: kube-prometheus-stack
###############################################################################
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  version          = "56.2.4"

  values = [
    templatefile("${path.module}/values/prometheus-stack.yaml.tpl", {
      cluster_name    = local.cluster_name
      grafana_password = random_password.grafana.result
      storage_class   = "gp3"
    })
  ]

  depends_on = [module.eks, kubernetes_storage_class_v1.gp3]
}

###############################################################################
# RDS — Aurora PostgreSQL (for application data)
###############################################################################
module "rds_aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "8.5.0"

  name   = "${var.project_name}-${var.environment}-db"
  engine = "aurora-postgresql"
  engine_version = "15.4"

  vpc_id               = module.vpc.vpc_id
  db_subnet_group_name = module.vpc.database_subnet_group_name
  security_group_rules = {
    eks_ingress = {
      source_security_group_id = module.eks.cluster_security_group_id
    }
  }

  instances = {
    writer = {
      instance_class = var.environment == "prod" ? "db.r6g.large" : "db.t3.medium"
    }
    reader = {
      instance_class     = var.environment == "prod" ? "db.r6g.large" : "db.t3.medium"
      publicly_accessible = false
    }
  }

  storage_encrypted   = true
  monitoring_interval = 60
  skip_final_snapshot = var.environment != "prod"

  tags = local.tags
}

###############################################################################
# Route53 + ACM
###############################################################################
data "aws_route53_zone" "main" {
  name = var.domain_name
}

resource "aws_acm_certificate" "main" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  subject_alternative_names = [
    var.domain_name,
    "monitoring.${var.domain_name}",
    "grafana.${var.domain_name}",
    "alertmanager.${var.domain_name}",
  ]

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Random resources
###############################################################################
resource "random_password" "grafana" {
  length           = 24
  special          = true
  override_special = "!#$%"
}

resource "aws_ssm_parameter" "grafana_password" {
  name  = "/${var.project_name}/${var.environment}/grafana/admin-password"
  type  = "SecureString"
  value = random_password.grafana.result
  tags  = local.tags
}

###############################################################################
# Cluster Autoscaler IAM Role
###############################################################################
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${local.cluster_name}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "cluster-autoscaler"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
          }
        }
      }
    ]
  })
}
