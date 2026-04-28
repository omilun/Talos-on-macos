variable "cluster_name" {
  description = "Talos cluster name (used in kubeconfig context and talosconfig)."
  type        = string
}

variable "talos_version" {
  description = "Talos Linux version (e.g. v1.13.0)."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version without 'v' prefix (e.g. 1.35.2)."
  type        = string
}

variable "talos_vip" {
  description = "Virtual IP assigned to the first control-plane interface for macOS access."
  type        = string
}

variable "tart_gateway" {
  description = "macOS Tart vmnet-shared bridge gateway used as the static-route next-hop."
  type        = string
}

variable "node_ips" {
  description = "Map of node name (e.g. talos-cp1) to IP address. Must contain all cluster nodes."
  type        = map(string)
}

variable "cp_node_names" {
  description = "Ordered list of control-plane node names. Index 0 is used as the etcd bootstrap node."
  type        = list(string)

  validation {
    condition     = length(var.cp_node_names) >= 1
    error_message = "At least one control-plane node is required."
  }
}

variable "common_patch" {
  description = "YAML machine-config patch applied to every node (kube-proxy off, CNI none, eBPF sysctls)."
  type        = string
}

variable "cp_patch" {
  description = "YAML machine-config patch applied to control-plane nodes only (disk, VIP)."
  type        = string
}

variable "worker_patch" {
  description = "YAML machine-config patch applied to worker nodes only (disk)."
  type        = string
}

variable "out_dir" {
  description = "Directory where kubeconfig.yaml and talosconfig are written."
  type        = string
}
