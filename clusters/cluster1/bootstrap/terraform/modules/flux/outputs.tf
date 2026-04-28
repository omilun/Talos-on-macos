output "flux_namespace" {
  description = "Namespace where Flux controllers are installed."
  value       = "flux-system"
}

output "git_repository_url" {
  description = "Git repository URL Flux is syncing from (empty if not configured)."
  value       = var.flux_git_repository_url
}

output "flux_hint" {
  description = "Commands to check Flux status and list managed resources."
  value       = "flux check --kubeconfig ${var.kubeconfig_path} && flux get all -A --kubeconfig ${var.kubeconfig_path}"
}
