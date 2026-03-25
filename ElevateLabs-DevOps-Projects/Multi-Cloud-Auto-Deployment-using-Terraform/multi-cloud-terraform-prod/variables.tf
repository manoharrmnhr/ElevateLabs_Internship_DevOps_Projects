# =============================================================================
#  variables.tf — All input variables for tri-cloud deployment
# =============================================================================

# ── General ───────────────────────────────────────────
variable "project_name" {
  description = "Prefix applied to every resource name"
  type        = string
  default     = "tricloud"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "project_name must be 3–20 lowercase alphanumeric chars or hyphens."
  }
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "owner" {
  description = "Owner tag applied to all resources (team or email)"
  type        = string
  default     = "devops-team"
}

variable "local_domain" {
  description = "Local domain name used by DNSMasq for routing simulation"
  type        = string
  default     = "multicloud.local"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed SSH access (restrict to your IP in production)"
  type        = string
  default     = "0.0.0.0/0"
}

# ── AWS ───────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region — us-east-1 is Free Tier eligible"
  type        = string
  default     = "us-east-1"
}

variable "aws_access_key" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
}

variable "aws_instance_type" {
  description = "EC2 instance type — t2.micro is Free Tier eligible"
  type        = string
  default     = "t2.micro"
}

variable "aws_ami_id" {
  description = "AMI ID — Ubuntu 22.04 LTS in us-east-1"
  type        = string
  default     = "ami-0c7217cdde317cfec"
}

variable "aws_key_name" {
  description = "Name of the existing EC2 Key Pair for SSH access"
  type        = string
}

# ── Azure ─────────────────────────────────────────────
variable "azure_subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  sensitive   = true
}

variable "azure_client_id" {
  description = "Azure Service Principal Application (Client) ID"
  type        = string
  sensitive   = true
}

variable "azure_client_secret" {
  description = "Azure Service Principal Client Secret"
  type        = string
  sensitive   = true
}

variable "azure_tenant_id" {
  description = "Azure Active Directory Tenant ID"
  type        = string
  sensitive   = true
}

variable "azure_location" {
  description = "Azure region — East US is Free Tier eligible"
  type        = string
  default     = "East US"
}

variable "azure_vm_size" {
  description = "Azure VM size — Standard_B1s is Free Tier eligible"
  type        = string
  default     = "Standard_B1s"
}

variable "azure_admin_username" {
  description = "Admin username for the Azure VM"
  type        = string
  default     = "azureuser"
}

variable "azure_ssh_public_key_path" {
  description = "Path to SSH public key file for Azure VM authentication"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# ── GCP ───────────────────────────────────────────────
variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region — us-central1 is Always Free eligible"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone within the region"
  type        = string
  default     = "us-central1-a"
}

variable "gcp_machine_type" {
  description = "GCP machine type — e2-micro is Always Free eligible"
  type        = string
  default     = "e2-micro"
}

variable "gcp_credentials_file" {
  description = "Path to GCP service-account JSON key file"
  type        = string
  default     = "~/.gcp/credentials.json"
}
