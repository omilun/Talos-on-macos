# Accessing Services: NodePort + Hostname Resolution

Quick reference for accessing your Talos cluster services.

## Recommended: HTTPS with Hostnames

**Setup** (one-time, 5 minutes):

```bash
# 1. Add to /etc/hosts
echo "192.168.64.6    ha.talos-on-mac.local argocd.ha.talos-on-mac.local grafana.ha.talos-on-mac.local prometheus.ha.talos-on-mac.local alertmanager.ha.talos-on-mac.local" | sudo tee -a /etc/hosts

# 2. Trust the CA
export KUBECONFIG=/tmp/kubeconfig.yaml
kubectl get secret -n networking wildcard-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/ca.crt

# 3. Verify
ping -c 1 argocd.ha.talos-on-mac.local
```

**Access**:

| Service | URL | Credentials |
|---------|-----|-----------|
| ArgoCD | `https://argocd.ha.talos-on-mac.local:32232` | `admin` / `rQwuRbjDeHtXkImn` |
| Grafana | `https://grafana.ha.talos-on-mac.local:31626` | `admin` / `change-me` |
| Prometheus | `https://prometheus.ha.talos-on-mac.local:32176` | — |
| Alertmanager | `https://alertmanager.ha.talos-on-mac.local:32227` | — |

**Browser**:
```bash
open https://argocd.ha.talos-on-mac.local:32232
open https://grafana.ha.talos-on-mac.local:31626
open https://prometheus.ha.talos-on-mac.local:32176
```

---

## Fallback: Direct IP + NodePort (No Setup)

If HTTPS doesn't work, use HTTP with IP:

```bash
# Find cluster node IP
kubectl get nodes -o wide | grep control-plane | head -1
# Example output: talos-jy0-m74   Ready   control-plane   192.168.64.6
```

| Service | NodePort | URL |
|---------|----------|-----|
| ArgoCD | 32232 | `http://192.168.64.6:32232` |
| Grafana | 31626 | `http://192.168.64.6:31626` |
| Prometheus | 32176 | `http://192.168.64.6:32176` |
| Alertmanager | 32227 | `http://192.168.64.6:32227` |

---

## Discovering NodePorts Dynamically

If ports change (e.g., after cluster recreate):

```bash
# Get all service NodePorts
kubectl get svc -A --sort-by=.spec.ports[0].nodePort
```

**Extract specific port**:
```bash
kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[0].nodePort}'
# Output: 32232
```

---

## kubectl Port-Forward (Alternative)

If NodePort isn't working:

```bash
# Forward ArgoCD to localhost:8080
kubectl port-forward -n argocd svc/argocd-server 8080:443 &

# Then access locally
open https://localhost:8080
```

**Note**: Only works while port-forward is running.

---

## Testing HTTPS (curl)

```bash
# With CA trusted (should work without warnings)
curl -v https://argocd.ha.talos-on-mac.local:32232/api/version

# With explicit CA path
curl --cacert /tmp/ca.crt https://argocd.ha.talos-on-mac.local:32232/api/version

# Skip verification (NOT RECOMMENDED)
curl -k https://argocd.ha.talos-on-mac.local:32232/api/version
```

---

## Phase 2: DNS in Cluster (Future)

When DNS server is deployed:

1. Remove `/etc/hosts` entries
2. Configure macOS DNS to `192.168.64.6`
3. Same URLs continue working automatically
4. No additional setup needed

See [dns-tls-setup.md](dns-tls-setup.md) for Phase 2 details.
