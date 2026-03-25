# =============================================================================
#  Multi-Cloud Auto Deployment — AWS + Azure + GCP (Free Tier)
#  File   : main.tf  (root module)
#  Author : DevOps Tri-Cloud Project
#  Purpose: Provision NGINX web servers on three clouds simultaneously
#           with health-check routing simulated via local DNSMasq.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# PROVIDER  ▸  AWS  (us-east-1 — Free Tier eligible)
# ──────────────────────────────────────────────────────────────────────────────
provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# PROVIDER  ▸  Azure  (East US — Free Tier eligible)
# ──────────────────────────────────────────────────────────────────────────────
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
  }

  subscription_id = var.azure_subscription_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
}

# ──────────────────────────────────────────────────────────────────────────────
# PROVIDER  ▸  GCP  (us-central1 — Always Free eligible)
# ──────────────────────────────────────────────────────────────────────────────
provider "google" {
  project     = var.gcp_project_id
  region      = var.gcp_region
  credentials = file(var.gcp_credentials_file)
}

# ──────────────────────────────────────────────────────────────────────────────
# RANDOM SUFFIX  ▸  ensures unique Azure resource names globally
# ──────────────────────────────────────────────────────────────────────────────
resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_string.suffix.result
}

# ──────────────────────────────────────────────────────────────────────────────
# MODULE  ▸  AWS Web Server
# ──────────────────────────────────────────────────────────────────────────────
module "aws_webserver" {
  source = "./modules/aws_webserver"

  project_name  = local.name_prefix
  environment   = var.environment
  aws_region    = var.aws_region
  instance_type = var.aws_instance_type
  ami_id        = var.aws_ami_id
  key_name      = var.aws_key_name
  allowed_cidr  = var.allowed_ssh_cidr
}

# ──────────────────────────────────────────────────────────────────────────────
# MODULE  ▸  Azure Web Server
# ──────────────────────────────────────────────────────────────────────────────
module "azure_webserver" {
  source = "./modules/azure_webserver"

  project_name    = local.name_prefix
  environment     = var.environment
  location        = var.azure_location
  vm_size         = var.azure_vm_size
  admin_username  = var.azure_admin_username
  ssh_public_key  = file(var.azure_ssh_public_key_path)
  suffix          = local.suffix
  allowed_ssh_ip  = var.allowed_ssh_cidr
}

# ──────────────────────────────────────────────────────────────────────────────
# MODULE  ▸  GCP Web Server
# ──────────────────────────────────────────────────────────────────────────────
module "gcp_webserver" {
  source = "./modules/gcp_webserver"

  project_name  = local.name_prefix
  environment   = var.environment
  gcp_project   = var.gcp_project_id
  gcp_region    = var.gcp_region
  gcp_zone      = var.gcp_zone
  machine_type  = var.gcp_machine_type
}

# ──────────────────────────────────────────────────────────────────────────────
# LOCAL FILES  ▸  DNSMasq config (generated after IPs are known)
# ──────────────────────────────────────────────────────────────────────────────
resource "local_file" "dnsmasq_config" {
  filename        = "${path.module}/dnsmasq/dnsmasq.conf"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/dnsmasq.conf.tpl", {
    aws_ip   = module.aws_webserver.public_ip
    azure_ip = module.azure_webserver.public_ip
    gcp_ip   = module.gcp_webserver.public_ip
    domain   = var.local_domain
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# LOCAL FILES  ▸  Health-check & routing script
# ──────────────────────────────────────────────────────────────────────────────
resource "local_file" "health_check" {
  filename        = "${path.module}/scripts/health_check.sh"
  file_permission = "0755"
  content = templatefile("${path.module}/templates/health_check.sh.tpl", {
    aws_ip   = module.aws_webserver.public_ip
    azure_ip = module.azure_webserver.public_ip
    gcp_ip   = module.gcp_webserver.public_ip
    domain   = var.local_domain
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# LOCAL FILES  ▸  Deployment summary JSON
# ──────────────────────────────────────────────────────────────────────────────
resource "local_file" "deployment_summary" {
  filename        = "${path.module}/docs/deployment_summary.json"
  file_permission = "0644"
  content = jsonencode({
    project     = var.project_name
    environment = var.environment
    deployed_at = timestamp()
    endpoints = {
      aws   = "http://${module.aws_webserver.public_ip}"
      azure = "http://${module.azure_webserver.public_ip}"
      gcp   = "http://${module.gcp_webserver.public_ip}"
    }
    health_checks = {
      aws   = "http://${module.aws_webserver.public_ip}/health"
      azure = "http://${module.azure_webserver.public_ip}/health"
      gcp   = "http://${module.gcp_webserver.public_ip}/health"
    }
    dns = {
      primary   = "multicloud.local → ${module.aws_webserver.public_ip}"
      secondary = "azure.multicloud.local → ${module.azure_webserver.public_ip}"
      tertiary  = "gcp.multicloud.local → ${module.gcp_webserver.public_ip}"
    }
  })
}
