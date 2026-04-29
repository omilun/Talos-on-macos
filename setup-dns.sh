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
DNS_SERVER="192.168.64.7"
DNS_PORT="30053"
INGRESS_IP="192.168.64.10"
MODE="${1:-interactive}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}✅${NC} $*"; }
warn() { echo -e "${YELLOW}⚠️ ${NC} $*"; }

echo "=== Talos-on-mac Setup ==="
echo "Domain: ${DOMAIN}"
echo ""

# ── Step 1: DNS Resolver ──────────────────────────────────────────────────────
if ! dig @"$DNS_SERVER" -p "$DNS_PORT" argocd."$DOMAIN" +short +timeout=3 &>/dev/null; then
  warn "DNS server not reachable at ${DNS_SERVER}:${DNS_PORT}"
  warn "Make sure cluster is running: kubectl get pods -n networking"
  exit 1
fi

RESOLVED=$(dig @"$DNS_SERVER" -p "$DNS_PORT" argocd."$DOMAIN" +short 2>/dev/null)
info "DNS server reachable — argocd.${DOMAIN} → $RESOLVED"

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

CA_NAME="tart-lab Root CA"
already_trusted() {
  security find-certificate -c "$CA_NAME" /Library/Keychains/System.keychain &>/dev/null
}

if already_trusted; then
  info "CA '${CA_NAME}' already trusted — skipping"
else
  # Delegate to trust-ca.sh
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
