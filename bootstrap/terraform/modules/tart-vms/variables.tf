variable "nodes" {
  description = "Map of VM name to node configuration."
  type = map(object({
    role      = string
    mac       = string
    cpu       = number
    memory_gb = number
  }))

  validation {
    condition = alltrue([
      for name, cfg in var.nodes :
      contains(["controlplane", "worker"], cfg.role)
    ])
    error_message = "Each node role must be either 'controlplane' or 'worker'."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.nodes :
      can(regex("^([0-9a-f]{2}:){5}[0-9a-f]{2}$", lower(cfg.mac)))
    ])
    error_message = "Each node MAC address must be a valid lowercase colon-separated hex string."
  }
}

variable "image_path" {
  description = "Absolute (or ~-prefixed) path to the Talos metal-arm64.raw disk image."
  type        = string
}

variable "disk_size_gb" {
  description = "Disk size for each VM in GiB."
  type        = number
  default     = 20
}

variable "nvram_src" {
  description = "Absolute path to the EFI NVRAM seed binary (nvram-arm64.bin)."
  type        = string
}

variable "ip_discovery_timeout" {
  description = "Seconds to wait for each VM's IP to appear in the ARP table."
  type        = number
  default     = 120

  validation {
    condition     = var.ip_discovery_timeout >= 30
    error_message = "ip_discovery_timeout must be at least 30 seconds."
  }
}
