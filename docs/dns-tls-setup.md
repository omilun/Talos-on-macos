# DNS and TLS Setup for macOS

This guide helps you configure clean HTTPS access to your Talos cluster services on macOS using local DNS and the pre-installed certificate.

## Quick Start (Recommended)

The cluster already has certificates installed for `*.local` domains (argocd.local, grafana.local, etc.).

**One-time setup (2 minutes)**:

```bash
# 1. Add service hostnames to /etc/hosts
echo "192.168.64.6    argocd.local grafana.local prometheus.local alertmanager.local" | sudo tee -a /etc/hosts

# 2. Trust the CA in macOS Keychain
export KUBECONFIG=/tmp/kubeconfig.yaml
kubectl get secret -n networking wildcard-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/talos-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/talos-ca.crt

# 3. Verify
ping -c 1 argocd.local
curl -v https://argocd.local:31223/api/version
open https://argocd.local:31223
```

**Result**: Clean HTTPS URLs with green lock icon (no certificate warnings)

---

## Service URLs & Ports

| Service | HTTPS | HTTP |
|---------|-------|------|
| ArgoCD | `https://argocd.local:31223` | `http://argocd.local:32232` |
| Grafana | — | `http://grafana.local:31626` |
| Prometheus | — | `http://prometheus.local:32176` |
| Alertmanager | — | `http://alertmanager.local:32227` |

**Credentials**:
- ArgoCD: `admin` / `rQwuRbjDeHtXkImn`
- Grafana: `admin` / `change-me`

---

## Understanding the Setup

### What's Already Configured

The cluster has cert-manager with a self-signed CA that generates certificates for:
- `*.local` (wildcard)
- `argocd.local`
- `grafana.local`
- `prometheus.local`
- `alertmanager.local`

This means services have valid TLS certificates right now!

### Why We Add to /etc/hosts

macOS DNS resolver needs to know that `argocd.local` → `192.168.64.6`. The `/etc/hosts` file tells the OS how to resolve these names.

Alternative: Deploy a DNS server in the cluster (see Phase 2 below).

### Why We Trust the CA

The certificate is self-signed (not from Let's Encrypt). macOS doesn't automatically trust it, so browsers show warnings. By adding the CA to the System Keychain, macOS recognizes all certificates signed by that CA as valid.

---

## Fallback: Direct IP:Port (No Setup)

If DNS or HTTPS doesn't work:

```bash
# HTTP (always works, no certificate issues)
open http://192.168.64.6:32232   # ArgoCD
open http://192.168.64.6:31626   # Grafana
open http://192.168.64.6:32176   # Prometheus
open http://192.168.64.6:32227   # Alertmanager

# HTTPS with IP (requires -k flag for curl, browser warnings)
curl -k https://192.168.64.6:31223/api/version   # ArgoCD
```

---

## Phase 2: Future - DNS Server in Cluster

*Plan for next week*

Instead of editing `/etc/hosts`, deploy a DNS server (CoreDNS or PowerDNS) in the cluster:

1. Deploy in `networking` namespace
2. Manage zones via Flux GitOps
3. Remove `/etc/hosts` entries
4. Multi-cluster support

Benefits:
- No local file edits
- Automatic service discovery
- Scalable to multiple clusters

---

## Troubleshooting

### DNS not resolving

```bash
# Check /etc/hosts entry
cat /etc/hosts | grep "argocd.local"

# Test DNS
nslookup argocd.local
# Should return: 192.168.64.6

# Flush cache
sudo dscacheutil -flushcache

# Verify cluster connectivity
kubectl get nodes
```

### HTTPS shows certificate warnings

```bash
# Verify CA is trusted
security find-certificate -c "wildcard" /Library/Keychains/System.keychain

# If not found, re-add:
kubectl get secret -n networking wildcard-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/ca.crt
```

### Service not accessible

```bash
# Verify service exists
kubectl get svc argocd-server -n argocd

# Check NodePort
kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[].nodePort}'

# Test with IP directly (no hostname)
curl http://192.168.64.6:32232/api/version
```

### HTTP works but HTTPS doesn't

This usually means the certificate is not trusted. Check:
1. Is the service actually serving HTTPS? (Check service configuration)
2. Is the CA trusted in your keychain?
3. Does the certificate cover `argocd.local`?

```bash
# Check what the certificate covers
kubectl get secret -n networking wildcard-tls -o yaml | grep dnsNames
```

---

## Reference: Service Configuration

**ArgoCD**:
- HTTP: port 8080 → NodePort 32232
- HTTPS: port 8080 (TLS termination) → NodePort 31223
- Same backend, different frontends

**Grafana, Prometheus, Alertmanager**:
- HTTP only (no native HTTPS)
- Can add HTTPS via ingress controller (future)

---

## Next Steps

1. Run Quick Start setup above (2 minutes)
2. Verify HTTPS works (open https://argocd.local:31223)
3. Log in to ArgoCD
4. Plan Phase 2 (DNS in cluster, next week)

For more details, see docs/accessing-services.md
