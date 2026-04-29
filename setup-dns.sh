#!/bin/bash
# setup-dns.sh
# One-time macOS DNS setup for Talos-on-mac cluster.
#
# Domain pattern: <service>.talos-tart-ha.talos-on-macos.com
# DNS is resolved by in-cluster CoreDNS exposed on NodePort 30053.
# /etc/resolver/talos-on-macos.com routes *.talos-on-macos.com to that server.
# No /etc/hosts entries. No mDNS conflicts.
#
# Services after setup:
#   https://argocd.talos-tart-ha.talos-on-macos.com
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

echo "=== Talos-on-mac DNS Setup ==="
echo "Domain: ${DOMAIN}"
echo ""

# Verify DNS server is reachable first
if ! dig @"$DNS_SERVER" -p "$DNS_PORT" argocd."$DOMAIN" +short &>/dev/null; then
  echo "❌ DNS server not reachable at ${DNS_SERVER}:${DNS_PORT}"
  echo "   Make sure cluster is running: kubectl get pods -n networking"
  exit 1
fi

RESOLVED=$(dig @"$DNS_SERVER" -p "$DNS_PORT" argocd."$DOMAIN" +short 2>/dev/null)
echo "✅ DNS server reachable — argocd.${DOMAIN} → $RESOLVED"
echo ""

# Configure /etc/resolver/talos-on-macos.com
# macOS routes all *.talos-on-macos.com queries to this nameserver.
# No mDNS conflict (unlike .local which is reserved by mDNS/Bonjour).
sudo mkdir -p /etc/resolver
printf "# Talos-on-mac cluster DNS\nnameserver %s\nport %s\nsearch_order 1\ntimeout 5\n" \
  "$DNS_SERVER" "$DNS_PORT" | sudo tee /etc/resolver/talos-on-macos.com > /dev/null
echo "✅ Configured /etc/resolver/talos-on-macos.com"

# Flush DNS cache
sudo dscacheutil -flushcache
echo "✅ DNS cache flushed"
echo ""

# Test resolution via system DNS
echo "Testing DNS resolution:"
for svc in argocd grafana prometheus alertmanager loki; do
  RESULT=$(dig "${svc}.${DOMAIN}" +short 2>/dev/null | head -1)
  if [ "$RESULT" = "$INGRESS_IP" ]; then
    echo "  ✅ ${svc}.${DOMAIN} → $RESULT"
  else
    echo "  ⚠️  ${svc}.${DOMAIN} → '${RESULT}' (expected $INGRESS_IP)"
  fi
done

echo ""
echo "=== Done! Access your services: ==="
echo "  open https://argocd.${DOMAIN}"
echo "  open https://grafana.${DOMAIN}     (admin / change-me)"
echo "  open https://prometheus.${DOMAIN}"
echo "  open https://alertmanager.${DOMAIN}"
echo "  open https://loki.${DOMAIN}"
echo ""
echo "Note: If HTTPS shows cert warning, trust the cluster CA:"
echo "  kubectl get secret root-ca-secret -n cert-manager \\"
echo "    -o jsonpath='{.data.tls\\.crt}' | base64 -d > /tmp/root-ca.crt"
echo "  sudo security add-trusted-cert -d -r trustRoot \\"
echo "    -k /Library/Keychains/System.keychain /tmp/root-ca.crt"
