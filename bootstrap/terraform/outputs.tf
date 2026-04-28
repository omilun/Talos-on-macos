output "kubeconfig_path" {
  description = "Absolute path to the generated kubeconfig.yaml file."
  value       = module.talos.kubeconfig_path
}

output "talosconfig_path" {
  description = "Absolute path to the generated talosconfig file."
  value       = module.talos.talosconfig_path
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint used by kubectl."
  value       = module.talos.cluster_endpoint
}

output "node_ips" {
  description = "Map of VM name to discovered IP address."
  value       = module.vms.node_ips
}

output "kubectl_hint" {
  description = "Export this to use kubectl against the cluster."
  value       = "export KUBECONFIG=${module.talos.kubeconfig_path}"
}

output "talosctl_hint" {
  description = "Export this to use talosctl against the cluster."
  value       = "export TALOSCONFIG=${module.talos.talosconfig_path}"
}

output "gateway_api_version" {
  description = "Installed Gateway API CRDs version."
  value       = module.gateway_api.gateway_api_version
}

output "flux_git_url" {
  description = "Git repository Flux is syncing from."
  value       = module.flux.git_repository_url
}

output "flux_hint" {
  description = "Commands to check Flux sync status."
  value       = module.flux.flux_hint
}

output "platform_urls" {
  description = "Service URLs. Add these hostnames to /etc/hosts pointing at the Gateway LoadBalancer IP."
  value = {
    argocd      = "https://argocd.local"
    grafana     = "https://grafana.local"
    prometheus  = "https://prometheus.local"
    alertmanager = "https://alertmanager.local"
  }
}

output "etc_hosts_hint" {
  description = "Get the Gateway LB IP, then add these lines to /etc/hosts on macOS."
  value       = "kubectl get gateway main-gateway -n networking -o jsonpath='{.status.addresses[0].value}' && echo ' argocd.local grafana.local prometheus.local alertmanager.local'"
}
