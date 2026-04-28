output "kubeconfig_path" {
  description = "Absolute path to the written kubeconfig.yaml file."
  value       = local_sensitive_file.kubeconfig.filename
}

output "talosconfig_path" {
  description = "Absolute path to the written talosconfig file."
  value       = local_sensitive_file.talosconfig.filename
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint (https://CP1_IP:6443)."
  value       = local.cluster_endpoint
}

output "kubeconfig_raw" {
  description = "Raw kubeconfig YAML content."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig_raw" {
  description = "Raw talosconfig YAML content."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "client_configuration" {
  description = "Talos client configuration object (for use in other modules/resources)."
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
}
