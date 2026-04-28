#!/bin/bash
# Setup script for dnsmasq + trusted CA on macOS
# Run this to enable https://argocd.local access with no warnings

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "Talos-on-macos: dnsmasq + Trusted CA Setup"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Step 1: Install dnsmasq
echo "Step 1/5: Installing dnsmasq..."
if command -v dnsmasq &> /dev/null; then
    echo "✅ dnsmasq already installed"
else
    brew install dnsmasq
    echo "✅ dnsmasq installed"
fi

# Step 2: Configure dnsmasq
echo ""
echo "Step 2/5: Configuring dnsmasq..."
sudo tee /usr/local/etc/dnsmasq.conf > /dev/null << 'CONFIG'
# Local development domain resolution
address=/.lab.local/192.168.64.6
address=/.local/192.168.64.6

# Cache settings
cache-size=10000
log-queries

# PID file
pid-file=/var/run/dnsmasq.pid
CONFIG

echo "✅ dnsmasq configured"

# Step 3: Setup macOS DNS resolver
echo ""
echo "Step 3/5: Configuring macOS DNS resolver..."
sudo mkdir -p /etc/resolver

sudo tee /etc/resolver/local > /dev/null << 'DNS'
nameserver 127.0.0.1
DNS

sudo tee /etc/resolver/lab.local > /dev/null << 'DNS'
nameserver 127.0.0.1
DNS

echo "✅ macOS DNS resolver configured"

# Step 4: Start dnsmasq service
echo ""
echo "Step 4/5: Starting dnsmasq service..."
sudo brew services restart dnsmasq
sleep 2
echo "✅ dnsmasq service started"

# Step 5: Test DNS resolution
echo ""
echo "Step 5/5: Testing DNS resolution..."
sleep 1
DNS_RESULT=$(ping -c 1 argocd.local 2>&1 | grep "192.168.64.6" || true)
if [ -n "$DNS_RESULT" ]; then
    echo "✅ DNS resolution working!"
    echo "   argocd.local resolves to 192.168.64.6"
else
    echo "⚠️  DNS resolution might need restart. Try: sudo dscacheutil -flushcache"
fi

# Step 6: Extract and trust cert-manager CA
echo ""
echo "Step 6/5: Extracting cert-manager CA certificate..."
export KUBECONFIG=/tmp/kubeconfig.yaml

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

# Extract certificate
kubectl get secret -n networking wildcard-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > ~/wildcard-tls-ca.crt

echo "✅ Certificate extracted to ~/wildcard-tls-ca.crt"

# Trust the certificate
echo ""
echo "Step 7/5: Trusting certificate in macOS Keychain..."
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/wildcard-tls-ca.crt

echo "✅ Certificate added to System Keychain"

# Cleanup
rm ~/wildcard-tls-ca.crt

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ SETUP COMPLETE!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "You can now access services via HTTPS:"
echo ""
echo "  ArgoCD:       https://argocd.local:32232"
echo "  Prometheus:   https://prometheus.local:32176"
echo "  Grafana:      https://grafana.local:31626"
echo "  Alertmanager: https://alertmanager.local:32227"
echo ""
echo "All should work with no TLS warnings!"
echo ""
echo "Troubleshooting:"
echo "- If DNS doesn't resolve: sudo dscacheutil -flushcache"
echo "- If dnsmasq stops: sudo brew services restart dnsmasq"
echo "- Check dnsmasq status: sudo brew services list | grep dnsmasq"
echo ""
