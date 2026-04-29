# ── Talos / Kubernetes versions ──────────────────────────────────────────────

variable "talos_version" {
  description = "Talos Linux version to provision (e.g. v1.13.0)."
  type        = string
  default     = "v1.13.0"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.talos_version))
    error_message = "talos_version must be in the format vX.Y.Z (e.g. v1.13.0)."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to install (e.g. 1.35.2). Do not include the 'v' prefix."
  type        = string
  default     = "1.35.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be in the format X.Y.Z (e.g. 1.35.2), without a 'v' prefix."
  }
}

# ── Cluster identity ──────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the Talos/Kubernetes cluster. Used for kubeconfig context and Talos cluster name."
  type        = string
  default     = "talos-tart-ha"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be a valid DNS label (lowercase alphanumeric and hyphens, 3-63 chars)."
  }
}

variable "talos_vip" {
  description = "Virtual IP (VIP) for control-plane HA. Assigned to CP1's interface; reachable from macOS. Not used as cluster endpoint internally (Tart PRIVATE bridge limitation)."
  type        = string
  default     = "192.168.64.100"

  validation {
    condition     = can(cidrhost("${var.talos_vip}/32", 0))
    error_message = "talos_vip must be a valid IPv4 address."
  }
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "tart_bridge_gateway" {
  description = "macOS Tart vmnet-shared bridge gateway. VMs use this as the next-hop for /32 peer routes (PRIVATE bridge workaround)."
  type        = string
  default     = "192.168.64.1"

  validation {
    condition     = can(cidrhost("${var.tart_bridge_gateway}/32", 0))
    error_message = "tart_bridge_gateway must be a valid IPv4 address."
  }
}

# ── VM image ──────────────────────────────────────────────────────────────────

variable "image_path" {
  description = "Path to the Talos metal-arm64.raw disk image. If the file does not exist, Terraform downloads it automatically from factory.talos.dev."
  type        = string
  default     = "~/Downloads/metal-arm64.raw"
}

variable "talos_schematic_id" {
  description = "Talos factory schematic ID. Default is bare-metal arm64 with no extensions. Generate a custom one at https://factory.talos.dev."
  type        = string
  default     = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4b"
}

variable "disk_size_gb" {
  description = "Final disk size for each VM in GiB. The raw Talos image is sparse-extended to this size."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10 GiB (Talos requires ~4 GiB minimum)."
  }
}

# ── Node pools ────────────────────────────────────────────────────────────────
# Declare any number of pools. Each pool expands into `count` VMs.
# All commits from the same pool share CPU/memory/labels/taints.
#
# Example — 3 CP + 3 general workers + 2 high-memory workers:
#
#   node_pools = [
#     { name = "cp",      role = "controlplane", count = 3, cpu = 4, memory_gb = 4 },
#     { name = "worker",  role = "worker",        count = 3, cpu = 2, memory_gb = 4 },
#     { name = "fat",     role = "worker",        count = 2, cpu = 4, memory_gb = 8,
#       labels = { "tier" = "high-mem" },
#       taints = [{ key = "tier", value = "high-mem", effect = "NoSchedule" }] },
#   ]
#
# Generated VM names: <pool.name>-1, <pool.name>-2, …
# Generated MACs:     c6:21:11:aa:<pool_idx>:<node_idx> (deterministic, 1-based)

variable "node_pools" {
  description = "List of node pool definitions. Each pool generates `count` VMs with identical resources, Kubernetes labels, and taints."
  type = list(object({
    name      = string
    role      = string  # "controlplane" or "worker"
    count     = number
    cpu       = number
    memory_gb = number
    labels    = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string  # taint value (can be empty "")
      effect = string  # NoSchedule | PreferNoSchedule | NoExecute
    })), [])
  }))

  default = [
    {
      name      = "cp"
      role      = "controlplane"
      count     = 3
      cpu       = 2
      memory_gb = 4
    },
    {
      name      = "worker"
      role      = "worker"
      count     = 3
      cpu       = 2
      memory_gb = 4
    },
  ]

  validation {
    condition = alltrue([
      for pool in var.node_pools :
      contains(["controlplane", "worker"], pool.role)
    ])
    error_message = "Each pool role must be 'controlplane' or 'worker'."
  }

  validation {
    condition = alltrue([
      for pool in var.node_pools : pool.count >= 1
    ])
    error_message = "Each pool must have count >= 1."
  }

  validation {
    condition = alltrue([
      for pool in var.node_pools : pool.cpu >= 1
    ])
    error_message = "Each pool must have cpu >= 1."
  }

  validation {
    condition = alltrue([
      for pool in var.node_pools : pool.memory_gb >= 2
    ])
    error_message = "Each pool must have memory_gb >= 2."
  }

  validation {
    condition = length([for p in var.node_pools : p if p.role == "controlplane"]) >= 1
    error_message = "At least one controlplane pool is required."
  }
}

# ── Output paths ──────────────────────────────────────────────────────────────

variable "out_dir" {
  description = "Directory where kubeconfig.yaml, talosconfig, and other generated files are written."
  type        = string
  default     = "../../_out"
}

# ── Gateway API ───────────────────────────────────────────────────────────────

variable "gateway_api_version" {
  description = "Gateway API CRDs version to install (e.g. v1.2.1)."
  type        = string
  default     = "v1.2.1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.gateway_api_version))
    error_message = "gateway_api_version must start with 'v' (e.g. v1.2.1)."
  }
}

# ── Flux ──────────────────────────────────────────────────────────────────────

variable "flux_version" {
  description = "Flux CLI version to install. Leave empty for latest stable."
  type        = string
  default     = ""
}

variable "flux_git_repository_url" {
  description = "Git repository URL for Flux to sync (e.g. https://github.com/omilun/talos-on-macos). Leave empty to install Flux controllers only."
  type        = string
  default     = "https://github.com/omilun/talos-on-macos"
}

variable "flux_git_branch" {
  description = "Git branch for Flux to sync."
  type        = string
  default     = "main"
}

variable "flux_git_path" {
  description = "Path within the Git repository where Flux cluster manifests live. Defaults to gitops/clusters/<cluster_name>."
  type        = string
  default     = ""
}

variable "flux_github_token" {
  description = "GitHub personal access token (needed for private repos or flux bootstrap github)."
  type        = string
  default     = ""
  sensitive   = true
}

# ── macOS host setup ──────────────────────────────────────────────────────────

variable "macos_sudo_password" {
  description = "macOS sudo password for /etc/resolver and CA trust steps. If empty, setup-dns.sh will prompt interactively."
  type        = string
  default     = ""
  sensitive   = true
}

# ── macOS host setup ──────────────────────────────────────────────────────────

variable "skip_macos_setup" {
  description = "Set to true to skip the macOS DNS resolver and CA trust steps (useful in CI or non-macOS environments)."
  type        = bool
  default     = false
}
