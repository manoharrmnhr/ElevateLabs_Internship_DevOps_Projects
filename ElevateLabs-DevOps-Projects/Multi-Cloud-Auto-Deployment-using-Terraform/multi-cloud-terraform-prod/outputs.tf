# =============================================================================
#  outputs.tf — Tri-Cloud Deployment Outputs
# =============================================================================

# ── AWS Outputs ───────────────────────────────────────
output "aws_instance_id" {
  description = "AWS EC2 Instance ID"
  value       = module.aws_webserver.instance_id
}

output "aws_public_ip" {
  description = "AWS EC2 Elastic IP address"
  value       = module.aws_webserver.public_ip
}

output "aws_nginx_url" {
  description = "AWS NGINX web endpoint"
  value       = "http://${module.aws_webserver.public_ip}"
}

output "aws_health_url" {
  description = "AWS NGINX health-check endpoint"
  value       = "http://${module.aws_webserver.public_ip}/health"
}

# ── Azure Outputs ─────────────────────────────────────
output "azure_vm_name" {
  description = "Azure VM resource name"
  value       = module.azure_webserver.vm_name
}

output "azure_public_ip" {
  description = "Azure VM public IP address"
  value       = module.azure_webserver.public_ip
}

output "azure_nginx_url" {
  description = "Azure NGINX web endpoint"
  value       = "http://${module.azure_webserver.public_ip}"
}

output "azure_health_url" {
  description = "Azure NGINX health-check endpoint"
  value       = "http://${module.azure_webserver.public_ip}/health"
}

# ── GCP Outputs ───────────────────────────────────────
output "gcp_instance_name" {
  description = "GCP Compute Engine instance name"
  value       = module.gcp_webserver.instance_id
}

output "gcp_public_ip" {
  description = "GCP Compute Engine static external IP"
  value       = module.gcp_webserver.public_ip
}

output "gcp_nginx_url" {
  description = "GCP NGINX web endpoint"
  value       = "http://${module.gcp_webserver.public_ip}"
}

output "gcp_health_url" {
  description = "GCP NGINX health-check endpoint"
  value       = "http://${module.gcp_webserver.public_ip}/health"
}

# ── Combined Summary ──────────────────────────────────
output "deployment_summary" {
  description = "Full deployment overview"
  value = <<-EOT

  ╔══════════════════════════════════════════════════════════════╗
  ║          TRI-CLOUD DEPLOYMENT — LIVE ENDPOINTS               ║
  ╠══════════════════════════════════════════════════════════════╣
  ║  AWS   (us-east-1)    →  http://${module.aws_webserver.public_ip}
  ║  Azure (East US)      →  http://${module.azure_webserver.public_ip}
  ║  GCP   (us-central1)  →  http://${module.gcp_webserver.public_ip}
  ╠══════════════════════════════════════════════════════════════╣
  ║  DNS  multicloud.local       → AWS  (primary)
  ║  DNS  azure.multicloud.local → Azure
  ║  DNS  gcp.multicloud.local   → GCP
  ╠══════════════════════════════════════════════════════════════╣
  ║  Run validation:  ./scripts/health_check.sh
  ╚══════════════════════════════════════════════════════════════╝

  EOT
}
