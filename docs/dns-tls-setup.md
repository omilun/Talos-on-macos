# DNS and TLS Setup for macOS

This guide helps you configure clean HTTPS access to your Talos cluster services on macOS using dnsmasq (local DNS) and a trusted self-signed CA.

## Quick Start

Run the automated setup script:

```bash
chmod +x setup-dnsmasq.sh
./setup-dnsmasq.sh
```

The script will:
1. Install dnsmasq (if needed)
2. Configure local DNS for `*.local` domains
3. Configure macOS to use dnsmasq
4. Extract cert-manager's self-signed CA
5. Trust the CA in macOS Keychain
6. Verify everything works

**Time required**: ~5 minutes

After running the script, you can access services via HTTPS:
```bash
open https://argocd.local:32232
open https://grafana.local:31626
open https://prometheus.local:32176
```

## What It Does

### DNS Resolution
The setup configures dnsmasq to resolve:
- `*.local` → 192.168.64.6 (your primary cluster node)
- `*.lab.local` → 192.168.64.6

This means:
- `argocd.local` → 192.168.64.6:32232
- `grafana.local` → 192.168.64.6:31626
- `prometheus.local` → 192.168.64.6:32176

### HTTPS Certificates
The setup trusts cert-manager's self-signed CA certificate in your macOS Keychain. This means:
- ✅ HTTPS connections work without warnings
- ✅ No certificate errors in browsers
- ✅ Valid for all `*.local` and `*.lab.local` domains

## Manual Setup (if script fails)

### Step 1: Install dnsmasq

```bash
brew install dnsmasq
```

### Step 2: Configure dnsmasq

```bash
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
```

### Step 3: Configure macOS DNS Resolver

```bash
sudo mkdir -p /etc/resolver

# Setup .local domain
sudo tee /etc/resolver/local > /dev/null << 'DNS'
nameserver 127.0.0.1
DNS

# Setup .lab.local domain  
sudo tee /etc/resolver/lab.local > /dev/null << 'DNS'
nameserver 127.0.0.1
DNS
```

### Step 4: Start dnsmasq Service

```bash
sudo brew services restart dnsmasq
```

### Step 5: Test DNS Resolution

```bash
# Should return 192.168.64.6
ping argocd.local

# Should work without connection refused
curl -k https://argocd.local:32232/health
```

If DNS doesn't work, flush macOS DNS cache:
```bash
sudo dscacheutil -flushcache
```

### Step 6: Trust cert-manager CA

```bash
export KUBECONFIG=/tmp/kubeconfig.yaml

# Extract certificate
kubectl get secret -n networking wildcard-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > ~/wildcard-ca.crt

# Add to System Keychain
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/wildcard-ca.crt

# Cleanup
rm ~/wildcard-ca.crt
```

## Verification

### DNS Working?
```bash
# Should return 192.168.64.6
nslookup argocd.local

# Should return 192.168.64.6
dig argocd.local

# Should respond
ping argocd.local
```

### HTTPS Working?
```bash
# Should work without -k flag (no self-signed warning)
curl https://argocd.local:32232/health
```

### Certificate Trusted?
```bash
# Should work in browser without warnings
open https://argocd.local:32232

# Check certificate in browser:
# - Lock icon should show "Connection is secure"
# - Click lock → Certificate → Should not show "Not Trusted"
```

## Service Access URLs

Once setup is complete, access services at:

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| ArgoCD | https://argocd.local:32232 | admin / rQwuRbjDeHtXkImn |
| Grafana | https://grafana.local:31626 | admin / change-me |
| Prometheus | https://prometheus.local:32176 | — |
| Alertmanager | https://alertmanager.local:32227 | — |

## Why dnsmasq?

dnsmasq is the standard DNS solution for local development on macOS because:
- ✅ Used by Docker Desktop
- ✅ Used by Kubernetes for Mac
- ✅ Native macOS integration
- ✅ Handles wildcards automatically
- ✅ Zero configuration for new services
- ✅ Works completely offline

## Troubleshooting

### DNS not resolving
```bash
# Check dnsmasq is running
sudo brew services list | grep dnsmasq

# Restart dnsmasq
sudo brew services restart dnsmasq

# Flush macOS DNS cache
sudo dscacheutil -flushcache
```

### HTTPS certificate warnings
```bash
# Check if CA is trusted
security find-certificate -c "wildcard-tls" /Library/Keychains/System.keychain

# Re-extract and trust the certificate
export KUBECONFIG=/tmp/kubeconfig.yaml
kubectl get secret -n networking wildcard-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > ~/wildcard-ca.crt
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/wildcard-ca.crt
rm ~/wildcard-ca.crt
```

## Security Note

The self-signed CA is for local development only. It's perfect for your macOS laptop but not suitable for:
- Production servers
- Team sharing (each Mac needs its own CA)

For team sharing, buy a real domain and use Let's Encrypt with cert-manager.
