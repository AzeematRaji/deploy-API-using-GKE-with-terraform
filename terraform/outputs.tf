output "kubernetes_cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "api_service_ip" {
  description = "The IP address of the API service"
  value       = length(kubernetes_service.api_service.status.0.load_balancer.0.ingress) > 0 ? kubernetes_service.api_service.status.0.load_balancer.0.ingress[0].ip : "IP not yet assigned"
}