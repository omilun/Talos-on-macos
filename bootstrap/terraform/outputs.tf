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
  description = "Service URLs. Run setup-dns.sh once to configure DNS and CA trust on macOS."
  value = {
    argocd       = "https://argocd.talos-tart-ha.talos-on-macos.com"
    grafana      = "https://grafana.talos-tart-ha.talos-on-macos.com"
    prometheus   = "https://prometheus.talos-tart-ha.talos-on-macos.com"
    alertmanager = "https://alertmanager.talos-tart-ha.talos-on-macos.com"
    loki         = "https://loki.talos-tart-ha.talos-on-macos.com"
  }
}

output "macos_setup_hint" {
  description = "One-time macOS setup: configures DNS resolver and trusts the cluster CA."
  value       = "bash ${path.root}/../../setup-dns.sh"
}
