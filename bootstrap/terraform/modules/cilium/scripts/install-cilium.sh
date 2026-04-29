#!/usr/bin/env bash
# install-cilium.sh — Install Cilium CNI via Helm with full eBPF kube-proxy replacement.
#
# Design choices:
#   k8sServiceHost=localhost / k8sServicePort=7445  ->  KubePrism (local proxy on
#     every node). Avoids ARP/VIP reachability issues inside Tart vmnet-shared.
#   kubeProxyReplacement=true  ->  eBPF replaces kube-proxy entirely.
#   operator.replicas=1        ->  single-replica operator (dev cluster).
#   hubble.relay.enabled=true  ->  observability.
#
# Required environment variables:
#   KUBECONFIG      Path to kubeconfig.yaml
#
# Optional environment variables:
#   CILIUM_VERSION  Helm chart version (default: latest stable)

set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG is required}"

log()  { echo "[INFO]  $*" >&2; }
ok()   { echo "[OK]    $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

command -v helm    >/dev/null || err "helm not found. Install: https://helm.sh/docs/intro/install/"
command -v kubectl >/dev/null || err "kubectl not found."

# ── Helm repo ─────────────────────────────────────────────────────────────────
log "Adding / updating Cilium Helm repo..."
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update cilium --fail-on-repo-update-fail

# ── Resolve version ───────────────────────────────────────────────────────────
if [[ -n "${CILIUM_VERSION:-}" ]]; then
  version="$CILIUM_VERSION"
  log "Using requested Cilium version: $version"
else
  version=$(helm search repo cilium/cilium --output json \
    | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['version'])")
  log "Latest Cilium version: $version"
fi

# ── Wait for Kubernetes API + at least one node ───────────────────────────────
log "Waiting for Kubernetes API to be ready..."
timeout=300; elapsed=0
until node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ') \
      && (( node_count >= 1 )); do
  (( elapsed += 10 ))
  (( elapsed >= timeout )) && err "Kubernetes API not ready after ${timeout}s"
  sleep 10
done
log "$node_count node(s) registered"

# ── Remove Flannel if present (cluster provisioned without cni:none patch) ────
if kubectl get daemonset kube-flannel -n kube-system &>/dev/null; then
  log "Flannel detected — removing before installing Cilium..."
  kubectl delete daemonset      kube-flannel     -n kube-system 2>/dev/null || true
  kubectl delete configmap      kube-flannel-cfg -n kube-system 2>/dev/null || true
  kubectl delete clusterrolebinding flannel                     2>/dev/null || true
  kubectl delete clusterrole        flannel                     2>/dev/null || true
  kubectl delete serviceaccount     flannel      -n kube-system 2>/dev/null || true
  sleep 10
fi

# ── Install Cilium ────────────────────────────────────────────────────────────
log "Installing Cilium $version..."
helm upgrade --install cilium cilium/cilium \
  --version "$version" \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445 \
  --set ipam.mode=kubernetes \
  --set operator.replicas=1 \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set "cgroup.autoMount.enabled=false" \
  --set "cgroup.hostRoot=/sys/fs/cgroup" \
  --set "securityContext.capabilities.ciliumAgent={CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --set "securityContext.capabilities.cleanCiliumState={NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
  --set gatewayAPI.enabled=true \
  --set l2announcements.enabled=true \
  --set externalIPs.enabled=true \
  --set l7Proxy=true \
  --set envoy.enabled=true \
  --wait --timeout 8m

# ── Verify rollout ────────────────────────────────────────────────────────────
log "Waiting for Cilium DaemonSet rollout..."
kubectl rollout status daemonset/cilium          -n kube-system --timeout=5m
kubectl rollout status deployment/cilium-operator -n kube-system --timeout=3m

ok "Cilium $version installed and ready"
kubectl get pods -n kube-system -l k8s-app=cilium --no-headers >&2

# ── Restart operator to ensure Gateway API CRDs are watched ──────────────────
# The Gateway API CRDs are installed in a separate step (gateway_api module).
# If Cilium started before those CRDs existed, the operator won't be watching
# them. A single restart is cheap and guarantees GatewayClass/Gateway reconcile.
log "Restarting Cilium operator to pick up Gateway API CRDs..."
kubectl rollout restart deployment/cilium-operator -n kube-system
kubectl rollout status  deployment/cilium-operator -n kube-system --timeout=3m
ok "Cilium operator restarted — Gateway API controller active"
