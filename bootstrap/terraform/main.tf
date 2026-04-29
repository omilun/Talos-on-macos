# ── VM lifecycle ──────────────────────────────────────────────────────────────
module "vms" {
  source = "./modules/tart-vms"

  nodes        = local.nodes
  image_path   = var.image_path
  disk_size_gb = var.disk_size_gb
  nvram_src    = local.nvram_src
}

# ── Talos cluster (secrets, configs, apply, bootstrap, kubeconfig) ────────────
module "talos" {
  source = "./modules/talos"

  cluster_name       = var.cluster_name
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  talos_vip          = var.talos_vip
  tart_gateway       = var.tart_bridge_gateway

  node_ips      = module.vms.node_ips
  cp_node_names = local.cp_node_names

  common_patch = local.common_patch
  cp_patch     = local.cp_patch
  worker_patch = local.worker_patch

  out_dir = local.out_dir_abs
}

# ── Cilium CNI (kube-proxy replacement, eBPF, Hubble, Gateway API) ────────────
module "cilium" {
  source = "./modules/cilium"

  kubeconfig_path = module.talos.kubeconfig_path
  out_dir         = local.out_dir_abs

  depends_on = [module.talos]
}

# ── Gateway API CRDs ──────────────────────────────────────────────────────────
# Installs the standard Gateway API CRD bundle.
# Everything else (GatewayClass, Gateway, LBPool, HTTPRoutes) is managed by Flux.
module "gateway_api" {
  source = "./modules/gateway-api"

  kubeconfig_path     = module.talos.kubeconfig_path
  gateway_api_version = var.gateway_api_version

  depends_on = [module.cilium]
}

# ── Flux GitOps bootstrap ─────────────────────────────────────────────────────
# Installs Flux v2 controllers and points them at the gitops/ directory in this
# repository. After this step, Flux owns all platform components (cert-manager,
# ArgoCD, Prometheus, Grafana, Loki) via the gitops/ manifests.
module "flux" {
  source = "./modules/flux"

  kubeconfig_path         = module.talos.kubeconfig_path
  flux_version            = var.flux_version
  flux_git_repository_url = var.flux_git_repository_url
  flux_git_branch         = var.flux_git_branch
  flux_git_path           = var.flux_git_path
  flux_github_token       = var.flux_github_token

  depends_on = [module.gateway_api]
}

# ── macOS host setup (DNS resolver + CA trust) ────────────────────────────────
# Runs once after Flux bootstraps the cluster and cert-manager issues the CA.
# Idempotent: safe to re-run (trust-ca.sh and setup-dns.sh both check state).
#
# Skip on non-macOS or in CI: set var.skip_macos_setup = true
resource "null_resource" "macos_setup" {
  count = var.skip_macos_setup ? 0 : 1

  triggers = {
    # Re-run if cluster name or kubeconfig changes
    cluster_name    = var.cluster_name
    kubeconfig_path = module.talos.kubeconfig_path
  }

  # Wait for Flux to deploy cert-manager and issue the cluster CA
  # (cert-manager typically ready ~2 min after Flux bootstrap)
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for cert-manager CA to be ready..."
      KUBECONFIG="${module.talos.kubeconfig_path}" \
        kubectl wait --for=condition=Ready certificate/root-ca \
        -n cert-manager --timeout=300s 2>/dev/null || \
        echo "⚠️  cert-manager not ready yet — run setup-dns.sh manually later"

      echo "Configuring macOS DNS and trusting cluster CA..."
      KUBECONFIG="${module.talos.kubeconfig_path}" \
        bash "$(dirname "${path.module}")/../../setup-dns.sh" --non-interactive
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [module.flux]
}
