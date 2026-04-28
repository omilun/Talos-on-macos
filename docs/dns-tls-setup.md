# DNS and TLS Setup: Professional Naming with Bootstrap Support

This guide sets up production-ready DNS naming for your Talos cluster infrastructure, supporting both immediate access and future containerized DNS deployment via Flux.

## Architecture Overview

**Root Domain**: `talos-on-mac.local` (private infrastructure domain)  
**Cluster Identifier**: `ha.talos-on-mac.local` (your HA cluster)  
**Service Pattern**: `<service>.ha.talos-on-mac.local`

This naming scheme:
- ✅ Works from cluster bootstrap (before dashboards are running)
- ✅ Supports multi-cluster federation (future: `c2.talos-on-mac.local`, `dev.talos-on-mac.local`)
- ✅ Single wildcard certificate covers all services and clusters
- ✅ GitOps-native (works with Flux-managed infrastructure)

---

## Phase 1: Immediate Access (Manual DNS + HTTPS)

**Time**: 5 minutes | **Setup**: One-time | **Complexity**: Simple

This phase gets you HTTPS access immediately while Phase 2 (containerized DNS) is being planned.

### Quick Start

```bash
# 1. Add cluster hostname to /etc/hosts
echo "192.168.64.6    ha.talos-on-mac.local argocd.ha.talos-on-mac.local grafana.ha.talos-on-mac.local prometheus.ha.talos-on-mac.local alertmanager.ha.talos-on-mac.local" | sudo tee -a /etc/hosts

# 2. Trust the CA in macOS Keychain
export KUBECONFIG=/tmp/kubeconfig.yaml
kubectl get secret -n networking wildcard-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/talos-on-mac-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/talos-on-mac-ca.crt

# 3. Verify DNS resolution
ping -c 1 argocd.ha.talos-on-mac.local

# 4. Verify HTTPS (should show green lock in browser)
curl -v https://argocd.ha.talos-on-mac.local:32232/health 2>&1 | grep -E "subject:|issuer:"
```

### What Happens

1. **`/etc/hosts` entries** (static hostname resolution)
   - Temporary solution while DNS server is being prepared
   - macOS kernel resolves `ha.talos-on-mac.local` → `192.168.64.6`

2. **Certificate Trust** (macOS Keychain)
   - Extract `wildcard-tls` secret from cluster (created by cert-manager)
   - Add CA certificate to System Keychain
   - Result: Green lock icon, no browser warnings on HTTPS connections

3. **Service Access**
   ```bash
   # Clean HTTPS URLs
   https://argocd.ha.talos-on-mac.local:32232
   https://grafana.ha.talos-on-mac.local:31626
   https://prometheus.ha.talos-on-mac.local:32176
   https://alertmanager.ha.talos-on-mac.local:32227
   ```

### Verifying It Works

```bash
# 1. DNS resolution
nslookup argocd.ha.talos-on-mac.local
# Expected: Name: argocd.ha.talos-on-mac.local
#           Address: 192.168.64.6

# 2. HTTPS with curl (no -k flag needed = CA is trusted)
curl -v https://argocd.ha.talos-on-mac.local:32232/api/version
# Expected: HTTP 200, no certificate warnings

# 3. Browser test
open https://argocd.ha.talos-on-mac.local:32232
# Expected: Green lock icon, no "Insecure" warnings
```

---

## Phase 2: Production DNS in Cluster (Future)

**Time**: 1 hour | **Deployment**: Via Flux | **Complexity**: Intermediate

This phase removes static `/etc/hosts` entries by deploying a DNS server inside your cluster.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        macOS Host                            │
│  System Preferences → Network → DNS → 192.168.64.6:53       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                  Talos Cluster (Flux-managed)                │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              networking namespace                    │    │
│  │  ┌─────────────────────────────────────────────┐    │    │
│  │  │  CoreDNS or PowerDNS                        │    │    │
│  │  │  Authoritative for: *.talos-on-mac.local    │    │    │
│  │  │  Zone file (managed by Flux):               │    │    │
│  │  │  - ha.talos-on-mac.local → 192.168.64.6    │    │    │
│  │  │  - c2.talos-on-mac.local → 192.168.64.7    │    │    │
│  │  │  - *.ha.talos-on-mac.local → 192.168.64.6  │    │    │
│  │  └─────────────────────────────────────────────┘    │    │
│  │  Service: NodePort :30053                          │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### How It Works

1. **DNS Server Pod**: CoreDNS or PowerDNS runs in `networking` namespace
2. **Zone Management**: Zones stored in ConfigMap, managed by Flux
3. **Service Exposure**: NodePort :30053 exposes DNS to macOS
4. **macOS Configuration**: System Preferences points to `192.168.64.6:53`
5. **Multi-cluster Ready**: Add new zones for `c2`, `dev`, `prod` clusters automatically

### Implementation Steps

```bash
# Step 1: Create DNS ConfigMap with zone file
kubectl create configmap coredns-zones -n networking \
  --from-literal=talos-on-mac.zone="
*.talos-on-mac.local.  300  IN  A  192.168.64.6
ha.talos-on-mac.local. 300  IN  A  192.168.64.6
" --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Deploy CoreDNS (via Flux kustomization)
# See: clusters/ha/manifests/networking/coredns/

# Step 3: Expose as NodePort
kubectl patch svc -n networking coredns -p '{"spec":{"type":"NodePort","ports":[{"port":53,"nodePort":30053}]}}'

# Step 4: Configure macOS DNS
# System Preferences → Network → Advanced → DNS
# Add: 192.168.64.6:30053 (or use networksetup command)
```

### Benefits

- ✅ No `/etc/hosts` maintenance
- ✅ Scales automatically (add services via Ingress/Service)
- ✅ Multi-cluster coordination via single zone file
- ✅ Flux-managed (Infrastructure as Code)
- ✅ ExternalDNS integration (future) for automatic updates

---

## Phase 3: Full GitOps Federation (Future)

**Time**: 2-3 hours | **Scope**: Enterprise-ready | **Complexity**: Advanced

Once DNS server is deployed, enable:

1. **ExternalDNS**: Automatically populate zones from Ingress resources
2. **Multi-cluster discovery**: Services find each other via DNS
3. **Terraform DNS zones**: Manage zones as IaC
4. **Route53/PowerDNS API**: Production DNS infrastructure

---

## Certificate Management

### Current Setup

The certificate is managed by cert-manager with a self-signed CA:

```bash
# View certificate details
kubectl get certificate -n networking wildcard-local -o yaml

# View the secret
kubectl get secret -n networking wildcard-tls -o yaml

# Extract CA certificate
kubectl get secret -n networking wildcard-tls \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
```

### Wildcard Coverage

Single certificate `*.talos-on-mac.local` covers:
- `*.ha.talos-on-mac.local` (current cluster)
- `*.c2.talos-on-mac.local` (future)
- `*.dev.talos-on-mac.local` (future)
- Any subdomain: `argocd`, `prometheus`, `grafana`, etc.

### Trusting the CA

**macOS System Keychain** (one-time setup):

```bash
# Extract CA from cluster
kubectl get secret -n networking wildcard-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > ca.crt

# Trust in System Keychain
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ca.crt

# Verify it's trusted
security find-certificate -c "wildcard" /Library/Keychains/System.keychain
```

### Future: Let's Encrypt Integration

When you're ready to use a real domain (e.g., `talos-on-mac.io`):

1. Update cert-manager ClusterIssuer to use `letsencrypt-prod`
2. Update ACME email configuration
3. Certificates will auto-renew via Let's Encrypt
4. No macOS keychain changes needed (public CA)

---

## Troubleshooting

### DNS Not Resolving

```bash
# Check /etc/hosts entry
cat /etc/hosts | grep talos-on-mac.local

# Test DNS
nslookup argocd.ha.talos-on-mac.local
# Should return: 192.168.64.6

# Flush DNS cache
sudo dscacheutil -flushcache

# Verify cluster connectivity
kubectl get nodes
```

### HTTPS Certificate Warnings in Browser

**Problem**: Green lock missing, untrusted certificate warnings

**Solution**:
```bash
# Verify CA is trusted in Keychain
security find-certificate -c "wildcard" /Library/Keychains/System.keychain

# If not found, extract and trust again
kubectl get secret -n networking wildcard-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/ca.crt
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /tmp/ca.crt
```

### Service Not Accessible

```bash
# Verify service is running
kubectl get svc -A | grep -E "argocd|prometheus|grafana"

# Verify NodePort mapping
kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[].nodePort}'

# Test connectivity
curl -v https://argocd.ha.talos-on-mac.local:32232/health

# Check cluster node is up
kubectl get nodes -o wide
```

### curl/wget Certificate Errors

**With CA trusted in Keychain**:
```bash
# Should work without -k flag
curl https://argocd.ha.talos-on-mac.local:32232/api/version

# If you get errors, explicitly pass CA path
curl --cacert /tmp/talos-on-mac-ca.crt \
  https://argocd.ha.talos-on-mac.local:32232/api/version
```

---

## Migration: Phase 1 → Phase 2

When you're ready to remove `/etc/hosts` entries:

1. Deploy DNS server (Phase 2)
2. Verify DNS resolution works from both cluster and macOS
3. Remove `/etc/hosts` entries:
   ```bash
   sudo sed -i '' '/talos-on-mac\.local/d' /etc/hosts
   ```
4. Verify services still accessible via hostnames
5. Document zone file location for team (Phase 3)

---

## Reference: Naming Scheme

```
talos-on-mac.local/
├── ha.talos-on-mac.local/
│   ├── argocd.ha.talos-on-mac.local     (NodePort :32232)
│   ├── prometheus.ha.talos-on-mac.local (NodePort :32176)
│   ├── grafana.ha.talos-on-mac.local    (NodePort :31626)
│   ├── alertmanager.ha.talos-on-mac.local (NodePort :32227)
│   └── <any-future-service>.ha.talos-on-mac.local
│
├── c2.talos-on-mac.local/              (Future cluster 2)
│   ├── argocd.c2.talos-on-mac.local
│   ├── prometheus.c2.talos-on-mac.local
│   └── ...
│
└── dev.talos-on-mac.local/             (Future dev cluster)
    ├── argocd.dev.talos-on-mac.local
    └── ...
```

---

## Further Reading

- See [docs/architecture.md](architecture.md) for full system design
- See [clusters/ha/manifests/networking/](../clusters/ha/manifests/networking/) for DNS/cert-manager deployment
- See [docs/bootstrap-flow.md](bootstrap-flow.md) for Flux bootstrap process
