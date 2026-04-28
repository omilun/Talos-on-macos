#!/bin/bash
# setup-dns.sh
# One-time macOS DNS configuration for Talos-on-mac cluster.
#
# After this script:
#   curl https://argocd.local      ← works, no /etc/hosts, no ports
#   curl https://grafana.local
#   curl https://prometheus.local
#   curl https://alertmanager.local
#   curl https://loki.local

set -euo pipefail

DNS_SERVER="192.168.64.6"
DNS_PORT="30053"

echo "=== Talos-on-mac DNS Setup ==="
echo ""

# Verify DNS server is reachable first
if ! dig @$DNS_SERVER -p $DNS_PORT argocd.local +short &>/dev/null; then
  echo "❌ DNS server not reachable at ${DNS_SERVER}:${DNS_PORT}"
  echo "   Make sure cluster is running: kubectl get pods -n networking"
  exit 1
fi

RESOLVED=$(dig @$DNS_SERVER -p $DNS_PORT argocd.local +short 2>/dev/null)
echo "✅ DNS server reachable — argocd.local → $RESOLVED"
echo ""

# Configure /etc/resolver/local (per-domain DNS, not /etc/hosts)
sudo mkdir -p /etc/resolver
printf "# Talos-on-mac cluster DNS\nnameserver %s\nport %s\nsearch_order 1\ntimeout 5\n" \
  "$DNS_SERVER" "$DNS_PORT" | sudo tee /etc/resolver/local > /dev/null
echo "✅ Configured /etc/resolver/local"

# Flush DNS cache
sudo dscacheutil -flushcache
echo "✅ DNS cache flushed"
echo ""

echo "Testing DNS resolution:"
for svc in argocd grafana prometheus alertmanager loki; do
  RESULT=$(dig "$svc.local" +short 2>/dev/null | head -1)
  if [ "$RESULT" = "192.168.64.10" ]; then
    echo "  ✅ $svc.local → $RESULT"
  else
    echo "  ⚠️  $svc.local → '${RESULT}' (expected 192.168.64.10)"
  fi
done

echo ""
echo "=== Done! Access your services: ==="
echo "  open https://argocd.local       (admin / rQwuRbjDeHtXkImn)"
echo "  open https://grafana.local      (admin / change-me)"
echo "  open https://prometheus.local"
echo "  open https://alertmanager.local"
echo "  open https://loki.local"
