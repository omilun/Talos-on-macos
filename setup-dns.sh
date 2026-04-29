#!/usr/bin/env bash
# setup-dns.sh
# One-time macOS setup for Talos-on-mac cluster.
# Configures DNS resolver AND trusts the cluster CA certificate.
#
# Usage:
#   bash setup-dns.sh                    # interactive (opens CA trust GUI)
#   bash setup-dns.sh --non-interactive  # headless / CI / Ansible / Terraform
#
# After this script:
#   https://argocd.talos-tart-ha.talos-on-macos.com   🔒 green padlock
#   https://grafana.talos-tart-ha.talos-on-macos.com
#   https://prometheus.talos-tart-ha.talos-on-macos.com
#   https://alertmanager.talos-tart-ha.talos-on-macos.com
#   https://loki.talos-tart-ha.talos-on-macos.com

set -euo pipefail

CLUSTER="talos-tart-ha"
DOMAIN="${CLUSTER}.talos-on-macos.com"
DNS_PORT="30053"
CA_NAME="tart-lab Root CA"
MODE="${1:-interactive}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}✅${NC} $*"; }
warn() { echo -e "${YELLOW}⚠️ ${NC} $*"; }

echo "=== Talos-on-mac Setup ==="
echo "Domain: ${DOMAIN}"
echo ""

# ── Discover DNS server: first ready control-plane node ──────────────────────
# Uses kubectl so the IP is always correct regardless of which node is active.
DNS_SERVER=""
for ip in $(kubectl get nodes -l node-role.kubernetes.io/control-plane= \
    -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null); do
  if nc -z -w2 "$ip" "$DNS_PORT" 2>/dev/null; then
    DNS_SERVER="$ip"
    break
  fi
done
if [ -z "$DNS_SERVER" ]; then
  warn "CoreDNS NodePort not reachable on any control-plane node"
  warn "Make sure cluster is running: kubectl get pods -n networking"
  exit 1
fi
info "DNS server: ${DNS_SERVER}:${DNS_PORT}"

# ── Discover ingress IP: first ready nginx-controller pod's node ──────────────
# nginx runs as a DaemonSet with hostNetwork=true, so any worker node IP works.
# This avoids hardcoding a fixed IP that breaks when nodes restart.
INGRESS_IP=""
INGRESS_IP=$(kubectl get pods -n networking -l 'app.kubernetes.io/name=ingress-nginx' \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].status.hostIP}' 2>/dev/null || true)
if [ -z "$INGRESS_IP" ]; then
  # Fallback: any Linux worker node IP
  INGRESS_IP=$(kubectl get nodes -l kubernetes.io/os=linux \
    -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
fi
if [ -z "$INGRESS_IP" ]; then
  warn "Could not discover nginx ingress IP — DNS may point to wrong address"
  INGRESS_IP="unknown"
fi
info "Ingress IP: ${INGRESS_IP}"

# ── Update CoreDNS ConfigMap with discovered ingress IP ───────────────────────
# Only patch if the IP differs from what's currently configured.
CURRENT_CM_IP=$(kubectl get configmap external-coredns -n networking \
  -o jsonpath='{.data.Corefile}' 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1 || true)
if [ "$CURRENT_CM_IP" != "$INGRESS_IP" ] && [ "$INGRESS_IP" != "unknown" ]; then
  info "Updating CoreDNS ConfigMap: ${CURRENT_CM_IP:-none} → ${INGRESS_IP}"
  kubectl get configmap external-coredns -n networking -o yaml 2>/dev/null | \
    sed "s/${CURRENT_CM_IP}/${INGRESS_IP}/g" | \
    kubectl apply -f - 2>/dev/null || warn "Could not update CoreDNS ConfigMap — update manually if needed"
fi

# ── Configure macOS /etc/resolver ────────────────────────────────────────────
sudo mkdir -p /etc/resolver
printf "# Talos-on-mac cluster DNS\nnameserver %s\nport %s\nsearch_order 1\ntimeout 5\n" \
  "$DNS_SERVER" "$DNS_PORT" | sudo tee /etc/resolver/talos-on-macos.com > /dev/null
info "Configured /etc/resolver/talos-on-macos.com"
sudo dscacheutil -flushcache
info "DNS cache flushed"

echo ""
echo "Testing DNS resolution:"
for svc in argocd grafana prometheus alertmanager loki; do
  RESULT=$(dscacheutil -q host -a name "${svc}.${DOMAIN}" 2>/dev/null | awk '/ip_address/{print $2}')
  if [ "$RESULT" = "$INGRESS_IP" ]; then
    info "  ${svc}.${DOMAIN} → $RESULT"
  else
    warn "  ${svc}.${DOMAIN} → '${RESULT:-not resolved}' (expected $INGRESS_IP)"
  fi
done

# ── Step 2: CA Trust ──────────────────────────────────────────────────────────
echo ""
echo "=== Step 2: Trust Cluster CA ==="

already_trusted() {
  security find-certificate -c "$CA_NAME" /Library/Keychains/System.keychain &>/dev/null
}

if already_trusted; then
  info "CA '${CA_NAME}' already trusted — skipping"
else
  bash "${REPO_ROOT}/scripts/trust-ca.sh" "${MODE}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Done! Access your cluster: ==="
echo "  open https://argocd.${DOMAIN}"
echo "  open https://grafana.${DOMAIN}     (admin / change-me)"
echo "  open https://prometheus.${DOMAIN}"
echo "  open https://alertmanager.${DOMAIN}"
echo "  open https://loki.${DOMAIN}"
echo ""
if already_trusted; then
  info "CA trusted — all dashboards should show a green padlock 🔒"
else
  warn "CA not yet trusted — complete the Install Profile step then re-run"
fi
