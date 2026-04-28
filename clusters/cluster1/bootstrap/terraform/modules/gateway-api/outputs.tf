output "gateway_api_version" {
  description = "Installed Gateway API CRDs version."
  value       = var.gateway_api_version
}

output "crds_installed_hint" {
  description = "Command to verify Gateway API CRDs are installed."
  value       = "kubectl get crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io -o name"
}
