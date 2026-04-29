locals {
  # ── Node definitions ────────────────────────────────────────────────────────
  # Deterministic MACs ensure stable ARP-based IP discovery across reboots.
  nodes = {
    talos-cp1 = { role = "controlplane", mac = "c6:21:11:aa:bb:01", cpu = var.cp_cpu,    memory_gb = var.cp_memory_gb }
    talos-cp2 = { role = "controlplane", mac = "c6:21:11:aa:bb:02", cpu = var.cp_cpu,    memory_gb = var.cp_memory_gb }
    talos-cp3 = { role = "controlplane", mac = "c6:21:11:aa:bb:03", cpu = var.cp_cpu,    memory_gb = var.cp_memory_gb }
    talos-w1  = { role = "worker",       mac = "c6:21:11:aa:cc:01", cpu = var.worker_cpu, memory_gb = var.worker_memory_gb }
    talos-w2  = { role = "worker",       mac = "c6:21:11:aa:cc:02", cpu = var.worker_cpu, memory_gb = var.worker_memory_gb }
    talos-w3  = { role = "worker",       mac = "c6:21:11:aa:cc:03", cpu = var.worker_cpu, memory_gb = var.worker_memory_gb }
  }

  # Ordered CP names: first entry is bootstrapped (etcd seed node).
  cp_node_names = ["talos-cp1", "talos-cp2", "talos-cp3"]

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

  # NVRAM seed binary shipped in repo (eliminates Ubuntu clone step on clean machines).
  nvram_src = abspath("${path.root}/../../nvram-arm64.bin")
}
