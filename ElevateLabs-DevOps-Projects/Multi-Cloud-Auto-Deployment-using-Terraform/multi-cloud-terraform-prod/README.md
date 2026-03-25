# ☁️ Multi-Cloud Auto Deployment using Terraform
### AWS + Azure + GCP — Free Tier · NGINX · DNSMasq · Production Grade

[![Terraform](https://img.shields.io/badge/Terraform-≥1.6-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Free%20Tier-FF9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/free/)
[![Azure](https://img.shields.io/badge/Azure-Free%20Tier-0078D4?logo=microsoftazure&logoColor=white)](https://azure.microsoft.com/free/)
[![GCP](https://img.shields.io/badge/GCP-Free%20Tier-4285F4?logo=googlecloud&logoColor=white)](https://cloud.google.com/free)
[![NGINX](https://img.shields.io/badge/NGINX-Web%20Server-009639?logo=nginx&logoColor=white)](https://nginx.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> **Provision NGINX web servers across AWS, Azure, and GCP simultaneously with a single `terraform apply`. Validate all three with one health-check script. Zero vendor lock-in.**

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Architecture Diagram](#-architecture-diagram)
- [Project Structure](#-project-structure)
- [Free Tier Reference](#-free-tier-reference)
- [Prerequisites](#-prerequisites)
- [Step-by-Step Execution Guide](#-step-by-step-execution-guide)
  - [Phase 1 — Install Tools](#phase-1--install-all-tools)
  - [Phase 2 — AWS Setup](#phase-2--aws-account-setup)
  - [Phase 3 — Azure Setup](#phase-3--azure-account-setup)
  - [Phase 4 — GCP Setup](#phase-4--gcp-account-setup)
  - [Phase 5 — Configure & Deploy](#phase-5--configure--deploy)
  - [Phase 6 — DNSMasq Routing](#phase-6--configure-dnsmasq-routing)
  - [Phase 7 — Validate](#phase-7--validate-all-endpoints)
  - [Phase 8 — Dashboard Screenshots](#phase-8--capture-dashboard-screenshots)
  - [Phase 9 — Destroy](#phase-9--destroy-all-infrastructure)
- [Troubleshooting](#-troubleshooting)
- [Security Considerations](#-security-considerations)
- [Contributing](#-contributing)

---

## 🌐 Overview

This project demonstrates **production-grade Infrastructure as Code (IaC)** using Terraform to provision identical NGINX web servers across three major cloud platforms simultaneously:

| Cloud | Service | Instance Type | Region | Free Tier |
|-------|---------|--------------|--------|-----------|
| **AWS** | EC2 + Elastic IP | t2.micro | us-east-1 | 750 hrs/month (12 mo) |
| **Azure** | Linux VM + Public IP | Standard_B1s | East US | 750 hrs/month (12 mo) |
| **GCP** | Compute Engine + Static IP | e2-micro | us-central1 | Always Free |

Each server delivers:
- `/` — Branded cloud-specific landing page with live instance metadata
- `/health` — Nginx-served directory with JSON health payload
- `/health/index.json` — Structured JSON: `{"status":"healthy","cloud":"...","timestamp":"..."}`

**Local DNSMasq** simulates production DNS-based multi-cloud routing:
```
multicloud.local        → AWS  (primary)
azure.multicloud.local  → Azure
gcp.multicloud.local    → GCP
```

---

## 🏗 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DEVELOPER WORKSTATION                               │
│                                                                              │
│   ┌─────────────────┐   terraform apply    ┌────────────────────────────┐  │
│   │                 │──────────────────────►│  Terraform State (.tfstate) │  │
│   │  terraform CLI  │                       └────────────────────────────┘  │
│   │  (orchestrator) │                                                        │
│   └────────┬────────┘                                                        │
│            │ provisions simultaneously                                        │
│   ┌────────▼────────────────────────────────────────────────────────────┐   │
│   │              DNSMasq (port 5353) — Local DNS Router                 │   │
│   │   multicloud.local → AWS | azure.multicloud.local → Azure          │   │
│   │   gcp.multicloud.local → GCP                                        │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │ Internet
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                         ▼
┌────────────────┐   ┌────────────────────┐   ┌──────────────────────┐
│  AWS (us-east) │   │  Azure (East US)   │   │  GCP (us-central1)   │
│                │   │                    │   │                      │
│  ┌──────────┐  │   │  ┌──────────────┐  │   │  ┌────────────────┐  │
│  │   VPC    │  │   │  │    VNet      │  │   │  │  VPC Network   │  │
│  │10.10.0/16│  │   │  │  10.20.0/16  │  │   │  │  10.30.0.0/16  │  │
│  └────┬─────┘  │   │  └──────┬───────┘  │   │  └───────┬────────┘  │
│       │        │   │         │          │   │           │           │
│  ┌────▼─────┐  │   │  ┌──────▼───────┐  │   │  ┌───────▼────────┐  │
│  │  Public  │  │   │  │    Subnet    │  │   │  │    Subnet      │  │
│  │  Subnet  │  │   │  │ 10.20.1.0/24 │  │   │  │ 10.30.1.0/24   │  │
│  │10.10.1/24│  │   │  └──────┬───────┘  │   │  └───────┬────────┘  │
│  └────┬─────┘  │   │         │          │   │           │           │
│  ┌────▼─────┐  │   │  ┌──────▼───────┐  │   │  ┌───────▼────────┐  │
│  │ EC2      │  │   │  │  Linux VM    │  │   │  │  GCE Instance  │  │
│  │ t2.micro │  │   │  │ Standard_B1s │  │   │  │  e2-micro      │  │
│  │  NGINX   │  │   │  │    NGINX     │  │   │  │   NGINX        │  │
│  └────┬─────┘  │   │  └──────┬───────┘  │   │  └───────┬────────┘  │
│       │        │   │         │          │   │           │           │
│  ┌────▼─────┐  │   │  ┌──────▼───────┐  │   │  ┌───────▼────────┐  │
│  │Elastic IP│  │   │  │  Public IP   │  │   │  │   Static IP    │  │
│  │(static)  │  │   │  │   Standard   │  │   │  │   (external)   │  │
│  └──────────┘  │   │  └──────────────┘  │   │  └────────────────┘  │
│                │   │                    │   │                      │
│  SG: 80,443,22 │   │  NSG: 80,443,22    │   │  FW: 80,443,22,ICMP  │
│  IMDSv2 ON     │   │  OS Login ON       │   │  Shielded VM ON      │
│  CW Alarm      │   │  Zone 1            │   │  VPC Flow Logs ON    │
└────────────────┘   └────────────────────┘   └──────────────────────┘

                    Health Check Flow (scripts/health_check.sh)
                    ├── curl http://<AWS_IP>/health/index.json  → {"status":"healthy"}
                    ├── curl http://<AZURE_IP>/health/index.json → {"status":"healthy"}
                    ├── curl http://<GCP_IP>/health/index.json   → {"status":"healthy"}
                    └── dig @127.0.0.1 -p 5353 *.multicloud.local → IPs verified
```

---

## 📁 Project Structure

```
tri-cloud-terraform/
│
├── main.tf                          # Root: providers, module calls, local file generation
├── variables.tf                     # All input variables with validation
├── outputs.tf                       # Outputs: IPs, URLs, deployment summary
├── terraform.tfvars.example         # Template — copy to terraform.tfvars
├── .gitignore                       # Excludes secrets, state, generated files
│
├── modules/
│   ├── aws_webserver/
│   │   ├── main.tf                  # VPC·IGW·Subnet·SG·EC2·EIP·CloudWatch
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── templates/
│   │       └── userdata.sh.tpl      # Cloud-generic NGINX bootstrap (templatefile)
│   │
│   ├── azure_webserver/
│   │   ├── main.tf                  # ResourceGroup·VNet·Subnet·NSG·PublicIP·VM
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── gcp_webserver/
│       ├── main.tf                  # VPC·Subnet·3×Firewall·StaticIP·GCE·ServiceAccount
│       ├── variables.tf
│       └── outputs.tf
│
├── templates/
│   ├── dnsmasq.conf.tpl             # DNSMasq config (rendered with IPs post-deploy)
│   └── health_check.sh.tpl         # Health-check script (rendered with IPs post-deploy)
│
├── dnsmasq/
│   └── dnsmasq.conf                 # ← Auto-generated after `terraform apply`
│
├── scripts/
│   └── health_check.sh              # ← Auto-generated after `terraform apply`
│
└── docs/
    └── deployment_summary.json      # ← Auto-generated after `terraform apply`
```

---

## 💰 Free Tier Reference

### AWS Free Tier (12 months from account creation)
| Resource | Free Limit | Project Usage |
|----------|-----------|---------------|
| EC2 t2.micro | 750 hrs/month | 1 instance |
| EBS gp3 | 30 GB | 8 GB |
| Elastic IP | Free when attached | 1 |
| Data Transfer Out | 1 GB/month | Minimal |
| CloudWatch | 10 metrics, 1M API calls | Alarm only |

### Azure Free Tier (12 months from account creation)
| Resource | Free Limit | Project Usage |
|----------|-----------|---------------|
| Standard_B1s VM | 750 hrs/month | 1 VM |
| Standard LRS Managed Disk | 64 GB | 30 GB |
| Public IP (Standard) | Charged | ~$0.004/hr |
| Data Transfer | 5 GB egress | Minimal |

> **Azure Note:** Standard SKU Public IPs are **not** free. Use Basic SKU or expect ~$3–5/month if left running. Always `terraform destroy` after testing.

### GCP Always Free
| Resource | Free Limit | Project Usage |
|----------|-----------|---------------|
| e2-micro | 1 instance in us-central1 | 1 instance |
| Standard persistent disk | 30 GB/month | 10 GB |
| Static IP (in use) | Free | 1 |
| Egress | 1 GB/month (Americas) | Minimal |

---

## 🛠 Prerequisites

| Tool | Min Version | Install Guide |
|------|-------------|---------------|
| Terraform | 1.6.0 | [terraform.io/downloads](https://developer.hashicorp.com/terraform/downloads) |
| AWS CLI | 2.x | [docs.aws.amazon.com/cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| Azure CLI | 2.50+ | [learn.microsoft.com/cli](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) |
| gcloud CLI | Latest | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |
| DNSMasq | Any | System package manager |
| curl + dig | Any | Pre-installed on most systems |
| SSH key pair | RSA/Ed25519 | `ssh-keygen -t ed25519` |

---

## 🚀 Step-by-Step Execution Guide

---

### Phase 1 — Install All Tools

#### macOS
```bash
# Terraform
brew tap hashicorp/tap && brew install hashicorp/tap/terraform

# Cloud CLIs
brew install awscli azure-cli google-cloud-sdk

# DNS + Utils
brew install dnsmasq bind curl jq

# Verify all
terraform version && aws --version && az version && gcloud version
```

#### Ubuntu / Debian
```bash
# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# gcloud CLI
curl https://sdk.cloud.google.com | bash && exec -l $SHELL && gcloud init

# Utils
sudo apt install -y dnsmasq dnsutils curl jq
```

---

### Phase 2 — AWS Account Setup

#### 2a. Create IAM User with Required Permissions
```bash
# In AWS Console: IAM → Users → Create user
# Name: terraform-deployer
# Attach policies:
#   - AmazonEC2FullAccess
#   - AmazonVPCFullAccess
#   - CloudWatchFullAccess
# Create access key → Download CSV
```

#### 2b. Create EC2 Key Pair
```bash
# In AWS Console: EC2 → Key Pairs → Create key pair
# Name: tricloud-key  |  Type: RSA  |  Format: .pem
mv ~/Downloads/tricloud-key.pem ~/.ssh/
chmod 400 ~/.ssh/tricloud-key.pem
```

#### 2c. Configure AWS CLI
```bash
aws configure
# AWS Access Key ID:     <from CSV>
# AWS Secret Access Key: <from CSV>
# Default region:        us-east-1
# Default output format: json

# Verify
aws sts get-caller-identity
```

---

### Phase 3 — Azure Account Setup

#### 3a. Login to Azure CLI
```bash
az login
# A browser window opens → sign in with your Azure account
az account show   # Confirm your subscription
```

#### 3b. Create Service Principal for Terraform
```bash
# Get your subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Create Service Principal with Contributor role
SP=$(az ad sp create-for-rbac \
  --name "terraform-tricloud-sp" \
  --role Contributor \
  --scopes /subscriptions/$SUBSCRIPTION_ID \
  --output json)

# Extract values (save these!)
echo "ARM_CLIENT_ID:       $(echo $SP | jq -r .appId)"
echo "ARM_CLIENT_SECRET:   $(echo $SP | jq -r .password)"
echo "ARM_TENANT_ID:       $(echo $SP | jq -r .tenant)"
echo "ARM_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
```

#### 3c. Register Required Resource Providers
```bash
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.KeyVault

# Verify registration (wait 1-2 minutes)
az provider show --namespace Microsoft.Compute --query registrationState
```

#### 3d. Create SSH Key for Azure VM
```bash
# If you don't have a key pair:
ssh-keygen -t ed25519 -C "tricloud-azure" -f ~/.ssh/tricloud_azure_ed25519
# Public key path: ~/.ssh/tricloud_azure_ed25519.pub
```

---

### Phase 4 — GCP Account Setup

#### 4a. Create GCP Project & Enable APIs
```bash
# Create project
PROJECT_ID="tricloud-$(date +%s)"
gcloud projects create $PROJECT_ID --name="Tri-Cloud Demo"
gcloud config set project $PROJECT_ID

# Enable billing (required for Compute Engine)
# GCP Console → Billing → Link project to billing account

# Enable APIs
gcloud services enable compute.googleapis.com
gcloud services enable iam.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com

echo "GCP Project ID: $PROJECT_ID"
```

#### 4b. Create Service Account & Download Key
```bash
PROJECT_ID=$(gcloud config get-value project)

# Create service account
gcloud iam service-accounts create terraform-sa \
  --display-name="Terraform Service Account" \
  --project=$PROJECT_ID

# Grant Compute Admin role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:terraform-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.admin"

# Grant IAM Service Account User role (for SA attachment to VMs)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:terraform-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

# Download JSON key
mkdir -p ~/.gcp
gcloud iam service-accounts keys create ~/.gcp/credentials.json \
  --iam-account="terraform-sa@$PROJECT_ID.iam.gserviceaccount.com"
chmod 600 ~/.gcp/credentials.json

echo "Key saved to ~/.gcp/credentials.json"
```

---

### Phase 5 — Configure & Deploy

#### 5a. Clone the Repository
```bash
git clone https://github.com/YOUR_USERNAME/tri-cloud-terraform.git
cd tri-cloud-terraform
```

#### 5b. Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with **all your real values**:
```hcl
# ── General
project_name     = "tricloud"
environment      = "dev"
owner            = "your-name"
local_domain     = "multicloud.local"
allowed_ssh_cidr = "YOUR_PUBLIC_IP/32"   # curl ifconfig.me

# ── AWS
aws_access_key    = "AKIAIOSFODNN7EXAMPLE"
aws_secret_key    = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
aws_region        = "us-east-1"
aws_instance_type = "t2.micro"
aws_ami_id        = "ami-0c7217cdde317cfec"
aws_key_name      = "tricloud-key"

# ── Azure
azure_subscription_id     = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
azure_client_id           = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
azure_client_secret       = "your-azure-sp-secret"
azure_tenant_id           = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
azure_location            = "East US"
azure_vm_size             = "Standard_B1s"
azure_admin_username      = "azureuser"
azure_ssh_public_key_path = "~/.ssh/tricloud_azure_ed25519.pub"

# ── GCP
gcp_project_id       = "tricloud-1234567890"
gcp_region           = "us-central1"
gcp_zone             = "us-central1-a"
gcp_machine_type     = "e2-micro"
gcp_credentials_file = "~/.gcp/credentials.json"
```

#### 5c. Initialize Terraform
```bash
terraform init
```
Expected output:
```
Initializing modules...
- aws_webserver in modules/aws_webserver
- azure_webserver in modules/azure_webserver
- gcp_webserver in modules/gcp_webserver

Initializing provider plugins...
- hashicorp/aws      v5.x.x ✓
- hashicorp/azurerm  v3.x.x ✓
- hashicorp/google   v5.x.x ✓
- hashicorp/local    v2.x.x ✓
- hashicorp/random   v3.x.x ✓

Terraform has been successfully initialized!
```

#### 5d. Review the Plan
```bash
terraform plan -out=tricloud.tfplan
```
Confirm the plan shows ~**22–26 resources** across all three clouds:
```
Plan: 24 to add, 0 to change, 0 to destroy.
```

#### 5e. Deploy All Three Clouds
```bash
terraform apply tricloud.tfplan
```
> ⏱️ **Estimated time:** 5–8 minutes

After completion, copy the output IPs:
```bash
# Save outputs to file
terraform output -json > docs/terraform_outputs.json

# Print summary
terraform output deployment_summary
```

> ⏳ **Wait 90–120 seconds** after apply completes for cloud-init/user-data scripts to finish installing NGINX.

---

### Phase 6 — Configure DNSMasq Routing

Terraform auto-generates `dnsmasq/dnsmasq.conf` with the real IPs. Now activate it:

#### macOS
```bash
# Copy generated config
sudo cp dnsmasq/dnsmasq.conf /usr/local/etc/dnsmasq.conf

# Restart DNSMasq
sudo brew services restart dnsmasq

# Configure macOS resolver
sudo mkdir -p /etc/resolver
cat <<EOF | sudo tee /etc/resolver/local
nameserver 127.0.0.1
port 5353
EOF

# Flush DNS cache
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

#### Ubuntu / Debian
```bash
# Stop systemd-resolved to free port 53
sudo systemctl disable --now systemd-resolved
sudo rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# Copy generated config
sudo cp dnsmasq/dnsmasq.conf /etc/dnsmasq.d/tricloud.conf

# Restart DNSMasq
sudo systemctl enable --now dnsmasq

# Add local DNS to resolv
echo "nameserver 127.0.0.1" | sudo tee -a /etc/resolv.conf
```

#### Verify DNSMasq
```bash
AWS_IP=$(terraform output -raw aws_public_ip)
GCP_IP=$(terraform output -raw gcp_public_ip)
AZURE_IP=$(terraform output -raw azure_public_ip)

# Test all three
dig +short @127.0.0.1 -p 5353 multicloud.local        # → AWS IP
dig +short @127.0.0.1 -p 5353 azure.multicloud.local   # → Azure IP
dig +short @127.0.0.1 -p 5353 gcp.multicloud.local     # → GCP IP
```

---

### Phase 7 — Validate All Endpoints

#### Run the Auto-Generated Health Check Script
```bash
chmod +x scripts/health_check.sh
./scripts/health_check.sh
```

**Expected output:**
```
  ╔════════════════════════════════════════════════════════════╗
  ║       TRI-CLOUD HEALTH CHECK — AWS + Azure + GCP          ║
  ║       2024-01-15 12:34:56 UTC                             ║
  ╚════════════════════════════════════════════════════════════╝

▶ AWS (us-east-1) — 54.123.45.67
  [PASS] Landing Page  (http://54.123.45.67/)         → HTTP 200
  [PASS] Health Route  (http://54.123.45.67/health)   → HTTP 200
  [PASS] Health JSON   → status=healthy

▶ Azure (East US) — 52.188.99.111
  [PASS] Landing Page  (http://52.188.99.111/)        → HTTP 200
  [PASS] Health Route  (http://52.188.99.111/health)  → HTTP 200
  [PASS] Health JSON   → status=healthy

▶ GCP (us-central1) — 34.72.88.200
  [PASS] Landing Page  (http://34.72.88.200/)         → HTTP 200
  [PASS] Health Route  (http://34.72.88.200/health)   → HTTP 200
  [PASS] Health JSON   → status=healthy

▶ DNS Resolution (DNSMasq @127.0.0.1:5353)
  [PASS] DNS multicloud.local       → 54.123.45.67
  [PASS] DNS aws.multicloud.local   → 54.123.45.67
  [PASS] DNS azure.multicloud.local → 52.188.99.111
  [PASS] DNS gcp.multicloud.local   → 34.72.88.200

  ══════════════════════════════════════════════════════════════
  RESULTS:  13 passed  |  0 failed  |  13 total checks
  ══════════════════════════════════════════════════════════════
```

#### Manual Verification Commands
```bash
# Fetch and pretty-print health JSON from each cloud
echo "=== AWS ===" && curl -sf http://$(terraform output -raw aws_public_ip)/health/index.json | jq .
echo "=== Azure ===" && curl -sf http://$(terraform output -raw azure_public_ip)/health/index.json | jq .
echo "=== GCP ===" && curl -sf http://$(terraform output -raw gcp_public_ip)/health/index.json | jq .

# Continuous monitoring (checks every 30 seconds)
./scripts/health_check.sh --loop 30
```

---

### Phase 8 — Capture Dashboard Screenshots

#### AWS Console
1. Log into [console.aws.amazon.com](https://console.aws.amazon.com)
2. **EC2 → Instances** — confirm `tricloud-dev-aws-web` → **Running**
3. **EC2 → Elastic IPs** — confirm EIP attached
4. **VPC Dashboard** — confirm VPC `tricloud-dev-vpc` created
5. **EC2 → Security Groups** — confirm ports 80, 443, 22 inbound rules
6. **CloudWatch → Alarms** — confirm `tricloud-dev-aws-cpu-high` alarm
7. Visit `http://<AWS_IP>` → Orange AWS landing page ✅

#### Azure Portal
1. Log into [portal.azure.com](https://portal.azure.com)
2. **Resource Groups** → `tricloud-dev-rg` → verify all resources
3. **Virtual Machines** → `tricloud-dev-azure-web` → **Running**
4. **Public IP addresses** → confirm static IP attached
5. **Network Security Groups** → confirm HTTP, HTTPS, SSH rules
6. Visit `http://<AZURE_IP>` → Blue Azure landing page ✅

#### GCP Console
1. Log into [console.cloud.google.com](https://console.cloud.google.com)
2. **Compute Engine → VM Instances** → `tricloud-dev-gcp-web` → **Running**
3. **VPC Network** → `tricloud-dev-vpc` — verify network
4. **VPC Network → Firewall** → confirm 3 firewall rules
5. **VPC Network → External IP Addresses** → confirm static IP
6. Visit `http://<GCP_IP>` → Blue GCP landing page ✅

---

### Phase 9 — Destroy All Infrastructure

> ⚠️ **Always destroy when done to avoid unexpected charges!**

```bash
# Preview what will be removed
terraform plan -destroy -out=destroy.tfplan

# Execute destruction
terraform apply destroy.tfplan

# Manual verification — all should return empty
echo "--- AWS Instances ---"
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=tricloud" \
  --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name}' \
  --output table

echo "--- Azure Resource Group ---"
az group exists --name tricloud-dev-rg

echo "--- GCP Instances ---"
gcloud compute instances list --filter="name:tricloud"
```

---

## 🔧 Troubleshooting

### NGINX not responding (HTTP timeout)
```bash
# Wait 2 minutes for cloud-init to complete, then:

# SSH into AWS
ssh -i ~/.ssh/tricloud-key.pem ubuntu@<AWS_IP>
sudo cat /var/log/user-data.log
sudo systemctl status nginx

# SSH into Azure
ssh -i ~/.ssh/tricloud_azure_ed25519 azureuser@<AZURE_IP>
sudo cat /var/log/azure-init.log
sudo systemctl status nginx

# SSH into GCP
gcloud compute ssh tricloud-dev-gcp-web --zone=us-central1-a
sudo cat /var/log/startup-script.log
sudo systemctl status nginx
```

### Terraform: AWS auth error
```bash
aws sts get-caller-identity   # Must return your account info
# If not: aws configure --profile terraform && export AWS_PROFILE=terraform
```

### Terraform: Azure auth error
```bash
az account show   # Must show your subscription
# Re-authenticate: az login
# Verify SP: az ad sp show --id $AZURE_CLIENT_ID
```

### Terraform: GCP auth error
```bash
gcloud auth application-default login
# Verify SA key: gcloud auth activate-service-account --key-file ~/.gcp/credentials.json
```

### DNSMasq port 53 conflict (Ubuntu)
```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
# Edit /etc/dnsmasq.conf: port=5353
sudo systemctl restart dnsmasq
```

### Terraform state lock
```bash
# Get lock ID from error message, then:
terraform force-unlock <LOCK_ID>
```

### Azure Public IP returns 0.0.0.0
```bash
# Wait 30 seconds, then refresh:
terraform refresh
terraform output azure_public_ip
```

---

## 🔐 Security Considerations

| Item | Recommendation |
|------|---------------|
| SSH CIDR | Set `allowed_ssh_cidr = "YOUR_IP/32"` (not 0.0.0.0/0) |
| Terraform state | Use remote state (S3 + DynamoDB / Azure Storage / GCS) in production |
| Secrets | Use Vault, AWS Secrets Manager, or Azure Key Vault — never hardcode |
| TLS/HTTPS | Add ACM (AWS), App Gateway (Azure), or Cloud Armor (GCP) with Let's Encrypt |
| IMDSv2 | Enforced on AWS EC2 (`http_tokens = "required"`) |
| Shielded VM | Enabled on GCP (Secure Boot + vTPM + Integrity Monitoring) |
| OS Login | Enabled on GCP VM |
| Monitoring | CloudWatch alarm (AWS) — add Azure Monitor & GCP Cloud Monitoring for production |

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/add-oracle-cloud`
3. Commit: `git commit -m 'feat: add Oracle Cloud module'`
4. Push: `git push origin feat/add-oracle-cloud`
5. Open a Pull Request

Please run `terraform validate` and `terraform fmt -recursive` before submitting.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

<div align="center">

**Built with Terraform · AWS · Azure · GCP · NGINX · DNSMasq**

*One command. Three clouds. Zero lock-in.*

</div>
