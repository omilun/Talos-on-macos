# ── Gateway API CRDs ──────────────────────────────────────────────────────────
# Installs ONLY the Gateway API CRD bundle (standard channel).
# Must run after Cilium is installed (Cilium's gateway controller watches these CRDs).
#
# What Terraform manages here (Day 0):
#   - Gateway API CRDs (GatewayClass, Gateway, HTTPRoute, ReferenceGrant, etc.)
#
# What Flux manages after bootstrap (Day 1):
#   - GatewayClass resource (cilium)
#   - CiliumLoadBalancerIPPool (LB IP range)
#   - CiliumL2AnnouncementPolicy (ARP for macOS reachability)
#   - Shared main-gateway (networking namespace)
#   - All HTTPRoutes, cert-manager, ArgoCD, observability
#
# CRDs are never pruned on destroy — removing them would destroy all Gateway
# resources in the cluster and break Flux reconciliation.

resource "null_resource" "gateway_api_crds" {
  triggers = {
    version    = var.gateway_api_version
    kubeconfig = var.kubeconfig_path
    script_md5 = filemd5("${path.module}/scripts/install-gateway-api.sh")
  }

  provisioner "local-exec" {
    command     = "bash '${path.module}/scripts/install-gateway-api.sh'"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG          = var.kubeconfig_path
      GATEWAY_API_VERSION = var.gateway_api_version
    }
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "echo '[WARN] Gateway API CRDs intentionally retained on destroy — removing them would break Flux and all Gateway resources.' >&2"
    interpreter = ["/bin/bash", "-c"]
  }
}
