###############################################################################
# Outputs — Self-Healing Infrastructure
###############################################################################

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "kubeconfig_command" {
  description = "Command to update local kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "rds_cluster_endpoint" {
  description = "RDS Aurora cluster writer endpoint"
  value       = module.rds_aurora.cluster_endpoint
  sensitive   = true
}

output "grafana_password_ssm_path" {
  description = "SSM path to Grafana admin password"
  value       = aws_ssm_parameter.grafana_password.name
}

output "grafana_password_command" {
  description = "Command to retrieve Grafana password"
  value       = "aws ssm get-parameter --name ${aws_ssm_parameter.grafana_password.name} --with-decryption --query Parameter.Value --output text"
}

output "certificate_arn" {
  description = "ACM certificate ARN"
  value       = aws_acm_certificate.main.arn
}
