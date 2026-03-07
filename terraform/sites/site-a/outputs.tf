output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "mq_nlb_hint" {
  description = "Get MQ NLB DNS name after MQ service is deployed"
  value       = "kubectl get svc -n ibm-mq mq-ha-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "configure_kubectl" {
  description = "Configure kubeconfig for this cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
