###############################################################################
# Variables — Self-Healing Infrastructure (Production)
###############################################################################

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "self-healing"
}

variable "environment" {
  description = "Deployment environment (dev/staging/prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod"
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "intra_subnet_cidrs" {
  description = "Intra subnets for EKS control plane"
  type        = list(string)
  default     = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
}

variable "eks_cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "allowed_cidr_blocks" {
  description = "CIDRs allowed to access the EKS API"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict in production
}

variable "app_node_min" {
  description = "Min nodes in application node group"
  type        = number
  default     = 3
}

variable "app_node_max" {
  description = "Max nodes in application node group"
  type        = number
  default     = 20
}

variable "app_node_desired" {
  description = "Desired nodes in application node group"
  type        = number
  default     = 5
}

variable "domain_name" {
  description = "Route53 hosted zone domain"
  type        = string
  default     = "example.com"
}
