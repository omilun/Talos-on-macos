locals {
  # ── Node pool expansion ─────────────────────────────────────────────────────
  # Expand var.node_pools into a flat ordered list, preserving pool order and
  # per-pool node order. This list drives both VM creation and Talos config.
  #
  # MAC scheme: c6:21:11:aa:<pool_idx_hex>:<node_idx_hex>
  #   - c6:21:11:aa prefix = locally-administered, unicast, project-specific
  #   - pool_idx: 0-based index of the pool in var.node_pools (0x00–0xff)
  #   - node_idx: 1-based node number within the pool (0x01–0xff)
  # Deterministic MACs ensure stable ARP-based IP discovery across reboots.
  _node_list = flatten([
    for pool_idx, pool in var.node_pools : [
      for node_idx in range(pool.count) : {
        name      = format("%s-%d", pool.name, node_idx + 1)
        role      = pool.role
        mac       = format("c6:21:11:aa:%02x:%02x", pool_idx, node_idx + 1)
        cpu       = pool.cpu
        memory_gb = pool.memory_gb
        labels    = pool.labels
        taints    = pool.taints
      }
    ]
  ])

  # Full node map — used for Talos config (includes labels/taints).
  nodes = { for entry in local._node_list : entry.name => entry }

  # VM-only node map (strips k8s fields) — passed to tart-vms module.
  vm_nodes = {
    for entry in local._node_list : entry.name => {
      role      = entry.role
      mac       = entry.mac
      cpu       = entry.cpu
      memory_gb = entry.memory_gb
    }
  }

  # Ordered CP names (pool order preserved): index 0 is the etcd seed node.
  cp_node_names = [for entry in local._node_list : entry.name if entry.role == "controlplane"]

  # Per-node label/taint patches injected at apply time (empty string = skip).
  # Talos nodeTaints format: { "<key>" = "<value>:<effect>" }
  # For taints with no value use value = "" → ":NoSchedule" is valid in Talos.
  label_taint_patches = {
    for entry in local._node_list : entry.name => (
      length(entry.labels) > 0 || length(entry.taints) > 0
      ? yamlencode({
          machine = merge(
            length(entry.labels) > 0 ? { nodeLabels = entry.labels } : {},
            length(entry.taints) > 0 ? {
              nodeTaints = {
                for t in entry.taints : t.key => "${t.value}:${t.effect}"
              }
            } : {}
          )
        })
      : ""
    )
  }

  # Cluster-level patch that removes the node-role.kubernetes.io/control-plane
  # taint from all CP nodes, allowing normal workloads to be scheduled there.
  # Empty string when disabled so compact() drops it in the module.
  allow_scheduling_patch = var.allow_scheduling_on_controlplane ? yamlencode({
    cluster = { allowSchedulingOnControlPlane = true }
  }) : ""
  # Patch file contents are read at plan time and passed as strings to the talos
  # module so the module itself has no file-system dependencies.
  patches_dir = "${path.root}/../../patches"
  common_patch     = file("${local.patches_dir}/common-patch.yaml")
  cp_patch         = file("${local.patches_dir}/controlplane-patch.yaml")
  worker_patch     = file("${local.patches_dir}/worker-patch.yaml")

  # Resolve output directory relative to the terraform root.
  out_dir_abs = abspath(var.out_dir)

  # Flux GitOps path: use explicit var if set, otherwise derive from cluster name.
  # Each cluster gets its own entrypoint under gitops/clusters/<cluster_name>/
  flux_git_path = coalesce(var.flux_git_path, "gitops/clusters/${var.cluster_name}")

  # Resolve image path (expands ~ and makes absolute)
  image_path_abs = abspath(pathexpand(var.image_path))

  # NVRAM seed binary shipped in repo (eliminates Ubuntu clone step on clean machines).
  nvram_src = abspath("${path.root}/../../nvram-arm64.bin")
}
