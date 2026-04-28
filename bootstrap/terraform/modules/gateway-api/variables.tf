variable "kubeconfig_path" {
  description = "Absolute path to kubeconfig.yaml for cluster authentication."
  type        = string
}

variable "gateway_api_version" {
  description = "Gateway API CRDs version (e.g. v1.2.1). See https://gateway-api.sigs.k8s.io/releases."
  type        = string
  default     = "v1.2.1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.gateway_api_version))
    error_message = "gateway_api_version must start with 'v' (e.g. v1.2.1)."
  }
}
