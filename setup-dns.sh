#!/usr/bin/env bash
# setup-dns.sh
# One-time macOS setup for Talos-on-mac cluster.
# Configures DNS resolver AND trusts the cluster CA certificate.
#
# Usage:
#   bash setup-dns.sh                    # interactive (prompts for sudo password)
#   bash setup-dns.sh --non-interactive  # headless — reads SUDO_PASSWORD from env or .env
#
# Sudo password (checked in order):
#   1. SUDO_PASSWORD env var (set by Terraform or CI)
#   2. .env file at repo root:  SUDO_PASSWORD=yourpassword
#   3. Interactive prompt (if neither above is set)
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

echo "=== Talos-on-mac DNS Setup ==="
echo "Domain: ${DOMAIN}"
echo ""

# ── Sudo password resolution ──────────────────────────────────────────────────
# Load from .env file if present (never committed — see .gitignore)
if [ -f "${REPO_ROOT}/.env" ]; then
  # shellcheck disable=SC1091
  set -o allexport; source "${REPO_ROOT}/.env"; set +o allexport
fi

# Prompt interactively if still not set
if [ -z "${SUDO_PASSWORD:-}" ]; then
  read -rs -p "macOS sudo password (needed for /etc/resolver): " SUDO_PASSWORD
  echo ""
fi

# Wrapper so we never call bare sudo (works headless and interactive)
run_sudo() { echo "$SUDO_PASSWORD" | sudo -S "$@" 2>/dev/null; }

# ── Discover DNS server: first reachable control-plane node on port 30053 ────
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
info "DNS server reachable — ${DNS_SERVER}:${DNS_PORT}"

# ── Discover Gateway LoadBalancer IP ─────────────────────────────────────────
# Cilium assigns an IP from CiliumLoadBalancerIPPool to the Gateway.
# setup-dns.sh updates the CoreDNS ConfigMap with this IP so DNS resolves correctly.
GATEWAY_IP=""
GATEWAY_IP=$(kubectl get gateway main-gateway -n networking \
  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
if [ -z "$GATEWAY_IP" ]; then
  # Fallback: first worker node IP (unlikely to be needed once Gateway is up)
  GATEWAY_IP=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' \
    -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
  [ -n "$GATEWAY_IP" ] && warn "Gateway LB IP not yet assigned — using worker node IP: ${GATEWAY_IP}"
fi
if [ -z "$GATEWAY_IP" ]; then
  warn "Could not discover Gateway IP — DNS may not resolve correctly"
  GATEWAY_IP="unknown"
fi
info "Gateway IP: ${GATEWAY_IP}"

# ── Update CoreDNS ConfigMap with discovered Gateway IP ──────────────────────
CURRENT_CM_IP=$(kubectl get configmap external-coredns -n networking \
  -o jsonpath='{.data.Corefile}' 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1 || true)
if [ "$CURRENT_CM_IP" != "$GATEWAY_IP" ] && [ "$GATEWAY_IP" != "unknown" ]; then
  info "Updating CoreDNS ConfigMap: ${CURRENT_CM_IP:-none} → ${GATEWAY_IP}"
  kubectl get configmap external-coredns -n networking -o yaml 2>/dev/null | \
    sed "s/${CURRENT_CM_IP:-192\.168\.64\.10}/${GATEWAY_IP}/g" | \
    kubectl apply -f - 2>/dev/null || warn "Could not update CoreDNS ConfigMap"
fi

# ── Configure macOS /etc/resolver ────────────────────────────────────────────
run_sudo mkdir -p /etc/resolver
printf "# Talos-on-mac cluster DNS\nnameserver %s\nport %s\nsearch_order 1\ntimeout 5\n" \
  "$DNS_SERVER" "$DNS_PORT" | run_sudo tee /etc/resolver/talos-on-macos.com > /dev/null
info "Configured /etc/resolver/talos-on-macos.com"
run_sudo dscacheutil -flushcache
info "DNS cache flushed"

echo ""
echo "Testing DNS resolution:"
for svc in argocd grafana prometheus alertmanager loki workflows registry pulse api.pulse; do
  RESULT=$(dscacheutil -q host -a name "${svc}.${DOMAIN}" 2>/dev/null | awk '/ip_address/{print $2}')
  if [ "$RESULT" = "$GATEWAY_IP" ]; then
    info "  ${svc}.${DOMAIN} → $RESULT"
  else
    warn "  ${svc}.${DOMAIN} → '${RESULT:-not resolved}' (expected $GATEWAY_IP)"
  fi
done

# ── Trust Cluster CA ──────────────────────────────────────────────────────────
echo ""
echo "=== Trusting Cluster CA ==="

already_trusted() {
  security find-certificate -c "$CA_NAME" /Library/Keychains/System.keychain &>/dev/null
}

if already_trusted; then
  info "CA '${CA_NAME}' already trusted — skipping"
else
  SUDO_PASSWORD="$SUDO_PASSWORD" bash "${REPO_ROOT}/scripts/trust-ca.sh" "${MODE}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Done! Access your cluster: ==="
echo "  open https://argocd.${DOMAIN}"
echo "  open https://grafana.${DOMAIN}     (admin / change-me)"
echo "  open https://prometheus.${DOMAIN}"
echo "  open https://alertmanager.${DOMAIN}"
echo "  open https://loki.${DOMAIN}"
echo "  open https://workflows.${DOMAIN}"
echo "  open https://registry.${DOMAIN}    (Zot OCI registry)"
echo "  open https://pulse.${DOMAIN}       (pulse demo app)"
echo ""
if already_trusted; then
  info "CA trusted — all dashboards should show a green padlock 🔒"
else
  warn "CA not yet trusted — complete the Install Profile step then re-run"
fi
