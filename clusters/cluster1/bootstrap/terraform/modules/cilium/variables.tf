variable "kubeconfig_path" {
  description = "Absolute path to kubeconfig.yaml used to authenticate against the cluster."
  type        = string
}

variable "out_dir" {
  description = "Directory containing kubeconfig.yaml (used as working dir for helm/kubectl)."
  type        = string
}

variable "cilium_version" {
  description = "Cilium Helm chart version to install. Leave empty to use the latest stable release."
  type        = string
  default     = ""
}
