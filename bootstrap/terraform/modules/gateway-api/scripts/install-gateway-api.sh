#!/usr/bin/env bash
# install-gateway-api.sh — Install Kubernetes Gateway API CRDs (standard channel).
#
# Terraform manages ONLY the CRD installation here. Everything else
# (GatewayClass, Gateway, LBPool, L2Policy, HTTPRoutes) is managed by Flux
# via the gitops/ directory in this repository.
#
# Required env vars: KUBECONFIG, GATEWAY_API_VERSION

set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${GATEWAY_API_VERSION:?GATEWAY_API_VERSION is required}"

log() { echo "[INFO]  $*" >&2; }
ok()  { echo "[OK]    $*" >&2; }
err() { echo "[ERROR] $*" >&2; exit 1; }

command -v kubectl >/dev/null || err "kubectl not found. Install: https://kubernetes.io/docs/tasks/tools/"

CRDS_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

log "Installing Gateway API CRDs ${GATEWAY_API_VERSION}..."
kubectl apply -f "${CRDS_URL}"

log "Waiting for Gateway API CRDs to be Established..."
for crd in \
    gatewayclasses.gateway.networking.k8s.io \
    gateways.gateway.networking.k8s.io \
    httproutes.gateway.networking.k8s.io \
    referencegrants.gateway.networking.k8s.io; do
  kubectl wait --for=condition=Established "crd/${crd}" --timeout=60s
  log "  ✓ ${crd}"
done

ok "Gateway API CRDs ${GATEWAY_API_VERSION} installed and ready"
log "Next: Flux will create the GatewayClass, Gateway, and LBPool resources from gitops/"
