locals {
  cp1_ip = var.node_ips[var.cp_node_names[0]]
  cp_ips = [for name in var.cp_node_names : var.node_ips[name]]

  # Cluster endpoint: CP1's direct DHCP IP, NOT the VIP.
  # Tart vmnet-shared PRIVATE bridge blocks VM-to-VM L2 forwarding so VMs
  # cannot ARP-resolve the VIP from each other.  CP1's IP is reachable from
  # all peers via /32 static routes through the macOS gateway.
  cluster_endpoint = "https://${local.cp1_ip}:6443"

  # SANs: VIP + all CP IPs (allows kubeconfig to connect via VIP from macOS).
  additional_sans = concat([var.talos_vip], local.cp_ips)

  # Force the correct installer image version.
  # talosctl gen config uses the binary version regardless of --talos-version,
  # which causes a downgrade loop on first boot when versions differ.
  installer_patch = yamlencode({
    machine = {
      install = {
        image = "ghcr.io/siderolabs/installer:${var.talos_version}"
      }
    }
  })

  # Per-node /32 static-route patches (Tart PRIVATE bridge workaround).
  # Each node gets a host route to every other node via the macOS gateway so
  # that intra-cluster traffic is forwarded at L3 through the host.
  route_patches = {
    for name, self_ip in var.node_ips :
    name => yamlencode({
      machine = {
        network = {
          interfaces = [{
            interface = "enp0s1"
            dhcp      = true
            routes = [
              for peer_name, peer_ip in var.node_ips :
              { network = "${peer_ip}/32", gateway = var.tart_gateway }
              if peer_name != name
            ]
          }]
        }
      }
    })
  }
}

# ── Cluster secrets (PKI, bootstrap token, etc.) ──────────────────────────────
# Stored in Terraform state. Use a remote backend (e.g. S3 + DynamoDB) in
# production to keep secrets out of local disk.
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version

  lifecycle {
    # Replacing secrets destroys the cluster. Require explicit override.
    prevent_destroy = true
  }
}

# ── Machine configuration: shared per role ────────────────────────────────────
# Common patches (kube-proxy, CNI, eBPF) and role patches are baked in here.
# Per-node route patches are injected at apply time to keep this config stable.

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = compact([
    var.common_patch,
    var.cp_patch,
    local.installer_patch,
    var.allow_scheduling_on_cp_patch,
  ])
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    var.common_patch,
    var.worker_patch,
    local.installer_patch,
  ]
}

# ── Apply configuration to every node ────────────────────────────────────────
# The per-node route patch is applied here so each node gets unique /32
# routes to its peers without needing a separate machine config per node.
resource "talos_machine_configuration_apply" "nodes" {
  for_each = var.node_ips

  client_configuration = talos_machine_secrets.this.client_configuration

  machine_configuration_input = (
    contains(var.cp_node_names, each.key)
    ? data.talos_machine_configuration.controlplane.machine_configuration
    : data.talos_machine_configuration.worker.machine_configuration
  )

  node     = each.value
  endpoint = each.value

  # Inject the per-node route patch + optional label/taint patch on top of
  # the shared machine config. compact() drops any empty strings.
  config_patches = compact([
    local.route_patches[each.key],
    lookup(var.node_extra_patches, each.key, ""),
  ])

  timeouts = {
    create = "5m"
  }
}

# ── Bootstrap etcd on the first control-plane node ───────────────────────────
resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp1_ip
  endpoint             = local.cp1_ip

  depends_on = [talos_machine_configuration_apply.nodes]

  timeouts = {
    create = "5m"
  }
}

# ── Fetch kubeconfig ──────────────────────────────────────────────────────────
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp1_ip
  endpoint             = local.cp1_ip

  depends_on = [talos_machine_bootstrap.this]

  timeouts = {
    read = "10m"
  }

  lifecycle {
    postcondition {
      condition     = self.kubeconfig_raw != ""
      error_message = "Kubeconfig is empty — cluster bootstrap may have failed. Check talosctl health."
    }
  }
}

# ── Talosconfig for talosctl ──────────────────────────────────────────────────
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.cp_ips
  nodes                = values(var.node_ips)
}

# ── Write configs to _out/ ────────────────────────────────────────────────────
resource "local_sensitive_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${var.out_dir}/kubeconfig.yaml"
  file_permission = "0600"

  depends_on = [talos_cluster_kubeconfig.this]
}

resource "local_sensitive_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = "${var.out_dir}/talosconfig"
  file_permission = "0600"
}

# ── Approve pending kubelet-serving CSRs ─────────────────────────────────────
# Talos does not auto-approve kubernetes.io/kubelet-serving CSRs.
# Run approval twice (with a delay) to catch CSRs from nodes that join late.
resource "null_resource" "approve_csrs" {
  depends_on = [local_sensitive_file.kubeconfig]

  triggers = {
    kubeconfig_id = local_sensitive_file.kubeconfig.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = "${var.out_dir}/kubeconfig.yaml"
    }
    command = <<-BASH
      for round in 1 2 3; do
        echo "[INFO] CSR approval round $round..."
        kubectl get csr -o name 2>/dev/null \
          | xargs -r kubectl certificate approve 2>/dev/null || true
        sleep 15
      done
      echo "[OK] CSR approval complete"
    BASH
  }
}
