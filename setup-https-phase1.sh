#!/bin/bash
# Phase 1 Setup: HTTPS Access with ha.talos-on-mac.local

set -e

echo "═══════════════════════════════════════════════════════════════════"
echo "  Talos on macOS: Phase 1 Setup (HTTPS Access)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check kubeconfig
if [ -z "$KUBECONFIG" ]; then
  export KUBECONFIG=/tmp/kubeconfig.yaml
fi

if [ ! -f "$KUBECONFIG" ]; then
  echo "❌ Error: kubeconfig not found at $KUBECONFIG"
  echo "   Please set KUBECONFIG or ensure /tmp/kubeconfig.yaml exists"
  exit 1
fi

echo "Using kubeconfig: $KUBECONFIG"
echo ""

# Step 1: Extract certificate
echo "Step 1: Extracting certificate from cluster..."
kubectl get secret -n networking wildcard-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/talos-on-mac-ca.crt
echo "✅ Certificate extracted to: /tmp/talos-on-mac-ca.crt"
echo ""

# Step 2: Add to /etc/hosts
echo "Step 2: Adding hostnames to /etc/hosts..."
cat >> /tmp/talos-on-mac-hosts.backup << 'HOSTS'
192.168.64.6    ha.talos-on-mac.local
192.168.64.6    argocd.ha.talos-on-mac.local
192.168.64.6    grafana.ha.talos-on-mac.local
192.168.64.6    prometheus.ha.talos-on-mac.local
192.168.64.6    alertmanager.ha.talos-on-mac.local
HOSTS

echo "Entries to add to /etc/hosts:"
cat /tmp/talos-on-mac-hosts.backup
echo ""
echo "Run this command to add to /etc/hosts:"
echo "  sudo tee -a /etc/hosts < /tmp/talos-on-mac-hosts.backup"
echo ""

# Step 3: Trust CA
echo "Step 3: Trusting CA in macOS System Keychain..."
echo "Run this command (you'll be prompted for your macOS password):"
echo "  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/talos-on-mac-ca.crt"
echo ""

# Step 4: Verify
echo "Step 4: Verification (run these after /etc/hosts and CA trust are configured):"
echo "  ping -c 1 argocd.ha.talos-on-mac.local"
echo "  curl -v https://argocd.ha.talos-on-mac.local:32232/api/version"
echo "  open https://argocd.ha.talos-on-mac.local:32232"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "  Setup Complete!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "1. Add to /etc/hosts (requires sudo password)"
echo "2. Trust CA in Keychain (requires sudo password)"
echo "3. Verify DNS and HTTPS work"
echo "4. Open services in browser"
echo ""
echo "See docs/dns-tls-setup.md for full details."
