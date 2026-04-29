# ── Talos disk image (auto-download if not present) ───────────────────────────
# Downloads the Talos metal-arm64.raw image from factory.talos.dev if the file
# does not already exist at var.image_path. Safe to re-run — skips if present.
resource "null_resource" "talos_image" {
  triggers = {
    image_path    = local.image_path_abs
    talos_version = var.talos_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      IMAGE="${local.image_path_abs}"
      if [ -f "$IMAGE" ]; then
        echo "[OK] Talos image already present: $IMAGE"
        exit 0
      fi
      echo "[INFO] Downloading Talos ${var.talos_version} image to $IMAGE ..."
      mkdir -p "$(dirname "$IMAGE")"
      curl -# -L \
        -o "$IMAGE" \
        "https://factory.talos.dev/image/${var.talos_schematic_id}/${var.talos_version}/metal-arm64.raw"
      echo "[OK] Image downloaded: $IMAGE"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# ── VM lifecycle ──────────────────────────────────────────────────────────────
module "vms" {
  source = "./modules/tart-vms"

  nodes        = local.nodes
  image_path   = local.image_path_abs
  disk_size_gb = var.disk_size_gb
  nvram_src    = local.nvram_src

  depends_on = [null_resource.talos_image]
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
  flux_git_path           = local.flux_git_path
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
    cluster_name    = var.cluster_name
    kubeconfig_path = module.talos.kubeconfig_path
  }

  # Wait for all Flux-managed components before running macOS host setup:
  #   1. cert-manager CA cert issued (needed for CA trust step)
  #   2. nginx DaemonSet fully rolled out (needed for DNS to work)
  #   3. CoreDNS NodePort reachable from macOS (needed for /etc/resolver to work)
  provisioner "local-exec" {
    environment = {
      KUBECONFIG    = module.talos.kubeconfig_path
      SUDO_PASSWORD = var.macos_sudo_password
    }
    command = <<-EOT
      set -euo pipefail

      echo "── Waiting for cert-manager CA certificate..."
      kubectl wait --for=condition=Ready certificate/root-ca \
        -n cert-manager --timeout=300s

      echo "── Waiting for wildcard TLS certificate..."
      kubectl wait --for=condition=Ready certificate/wildcard-cluster-tls \
        -n networking --timeout=300s

      echo "── Waiting for Cilium Gateway to get a LoadBalancer IP..."
      GW_IP=""
      for attempt in $(seq 1 30); do
        GW_IP=$(kubectl get gateway main-gateway -n networking \
          -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
        if [ -n "$GW_IP" ]; then
          echo "  Gateway LB IP: $GW_IP"
          break
        fi
        echo "  Waiting for Gateway LB IP... ($attempt/30)"
        sleep 10
      done
      if [ -z "$GW_IP" ]; then
        echo "WARNING: Gateway LB IP not assigned after 5 minutes — continuing anyway"
      fi

      echo "── Waiting for CoreDNS NodePort to be reachable..."
      COREDNS_IP=""
      for attempt in $(seq 1 30); do
        COREDNS_IP=$(kubectl get nodes \
          -l node-role.kubernetes.io/control-plane= \
          -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
        if [ -n "$COREDNS_IP" ] && nc -z -w2 "$COREDNS_IP" 30053 2>/dev/null; then
          echo "  CoreDNS reachable at $COREDNS_IP:30053"
          break
        fi
        echo "  Waiting for CoreDNS... ($attempt/30)"
        sleep 10
      done

      echo "── Configuring macOS DNS resolver and trusting cluster CA..."
      bash "$(dirname "${path.module}")/../../setup-dns.sh" --non-interactive
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [module.flux]
}
