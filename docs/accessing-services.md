# Accessing Services: Quick Reference

Your Talos cluster services are exposed as NodePort services with valid TLS certificates.

## Recommended: HTTPS with Hostnames

**Setup** (one-time, 2 minutes):

```bash
# 1. Add hostnames to /etc/hosts
echo "192.168.64.6    argocd.local grafana.local prometheus.local alertmanager.local" | sudo tee -a /etc/hosts

# 2. Trust the CA
export KUBECONFIG=/tmp/kubeconfig.yaml
kubectl get secret -n networking wildcard-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/talos-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/talos-ca.crt

# 3. Verify
ping -c 1 argocd.local
```

**Access**:

| Service | HTTPS | HTTP | Credentials |
|---------|-------|------|-----------|
| ArgoCD | https://argocd.local:31223 | http://argocd.local:32232 | admin / rQwuRbjDeHtXkImn |
| Grafana | — | http://grafana.local:31626 | admin / change-me |
| Prometheus | — | http://prometheus.local:32176 | — |
| Alertmanager | — | http://alertmanager.local:32227 | — |

**Browser**:
```bash
open https://argocd.local:31223
open http://grafana.local:31626
open http://prometheus.local:32176
```

---

## Fallback: Direct IP + NodePort (No Setup)

```bash
# Find cluster node IP
kubectl get nodes -o wide | grep control-plane | head -1
# Example: talos-jy0-m74   Ready   control-plane   192.168.64.6
```

| Service | Protocol | URL |
|---------|----------|-----|
| ArgoCD | HTTP | http://192.168.64.6:32232 |
| ArgoCD | HTTPS | https://192.168.64.6:31223 |
| Grafana | HTTP | http://192.168.64.6:31626 |
| Prometheus | HTTP | http://192.168.64.6:32176 |
| Alertmanager | HTTP | http://192.168.64.6:32227 |

---

## Testing with curl

```bash
# HTTP (always works)
curl http://192.168.64.6:32232/api/version

# HTTPS with hostname (requires CA trust setup)
curl https://argocd.local:31223/api/version

# HTTPS with IP (skip verification)
curl -k https://192.168.64.6:31223/api/version
```

---

## Port Reference

| Service | HTTP NodePort | HTTPS NodePort |
|---------|---------------|----------------|
| ArgoCD | 32232 | 31223 |
| Grafana | 31626 | N/A |
| Prometheus | 32176 | N/A |
| Alertmanager | 32227 | N/A |

See [dns-tls-setup.md](dns-tls-setup.md) for full setup details.
