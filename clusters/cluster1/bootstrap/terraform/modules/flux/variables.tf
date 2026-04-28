variable "kubeconfig_path" {
  description = "Absolute path to kubeconfig.yaml for cluster authentication."
  type        = string
}

variable "flux_version" {
  description = "Flux CLI version to install (e.g. v2.5.1). Leave empty to install the latest stable release."
  type        = string
  default     = ""
}

variable "flux_git_repository_url" {
  description = "Git repository URL for Flux to sync (e.g. https://github.com/org/gitops-repo). Leave empty to install Flux controllers only (no GitRepository source configured)."
  type        = string
  default     = ""
}

variable "flux_git_branch" {
  description = "Git branch for Flux to sync."
  type        = string
  default     = "main"
}

variable "flux_git_path" {
  description = "Path within the Git repository where Flux cluster manifests live."
  type        = string
  default     = "clusters/tart-lab"
}

variable "flux_github_token" {
  description = "GitHub personal access token for private repositories. Only used when flux_git_repository_url is set."
  type        = string
  default     = ""
  sensitive   = true
}
