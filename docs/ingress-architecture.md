# Kubernetes Ingress Architecture (The Right Way)

## Overview

Your cluster is now using **proper Kubernetes Ingress** architecture — no NodePorts needed!

### What Changed

**BEFORE** (Incorrect - documented earlier):
```
Client (macOS)
  ↓ /etc/hosts: 192.168.64.6
  ↓
  ↓ NodePort: argocd.local:32232, grafana.local:31626, etc.
  ↓ (Each service on different port — ugly!)
  ↓
Service (NodePort)
```

**AFTER** (Correct - Kubernetes native):
```
Client (macOS) 
  ↓ /etc/hosts: 192.168.64.10 argocd.local grafana.local prometheus.local alertmanager.local
  ↓
  ↓ HTTP/HTTPS: argocd.local, grafana.local, prometheus.local, alertmanager.local
  ↓ (Standard ports 80/443 — professional!)
  ↓
Ingress Controller (hostNetwork=true)
  ↓
Ingress Resources (route by hostname)
  ↓
Service → Pod
```

## How It Works

### 1. **Ingress Controller**
- Running in `ingress-nginx` namespace
- Pod binds directly to node network: 192.168.64.10
- Listens on standard ports: 80 (HTTP) and 443 (HTTPS)
- Configured with `hostNetwork: true` (necessary on Talos)

### 2. **Ingress Resources**
Each service has an Ingress resource that maps:
```yaml
Host: argocd.local       → Service: argocd-server:443
Host: grafana.local      → Service: kube-prometheus-stack-grafana:80
Host: prometheus.local   → Service: kube-prometheus-stack-prometheus:9090
Host: alertmanager.local → Service: kube-prometheus-stack-alertmanager:9093
```

### 3. **DNS Resolution** (Only Requirement)
Add to macOS `/etc/hosts`:
```
192.168.64.10  argocd.local grafana.local prometheus.local alertmanager.local
```

**That's it!** No certificate installation, no port numbers to remember.

## Why This Is Better

| Aspect | NodePorts | Ingress |
|--------|-----------|---------|
| **User Experience** | `argocd.local:32232` (remember ports!) | `argocd.local` (standard port 80/443) |
| **Scaling** | Each service = new port | All services = same ports |
| **Professional** | ❌ Not production-ready | ✅ Industry standard |
| **Kubernetes-native** | ❌ Workaround | ✅ Designed for this |
| **HTTPS Support** | ❌ Complex | ✅ Native via cert-manager |
| **Multi-service** | ❌ Port collision risk | ✅ Hostname-based routing |

## Current Status

✅ Ingress Controller running  
✅ Ingress resources created for all services  
✅ Tests passing (HTTP 302/308 = redirects to HTTPS)  
✅ Ready for DNS setup  

## Next Steps

### 1. Update /etc/hosts
```bash
echo "192.168.64.10  argocd.local grafana.local prometheus.local alertmanager.local" | sudo tee -a /etc/hosts
```

### 2. Verify DNS
```bash
ping -c 1 argocd.local
```

### 3. Access Services
```bash
open http://argocd.local
open http://grafana.local
open http://prometheus.local
open http://alertmanager.local
```

### 4. HTTPS (Optional)
If cert-manager has generated valid certs:
```bash
open https://argocd.local
```

## Technical Details

### PodSecurity Policy Exception
The ingress controller requires:
- `hostNetwork: true` (bind to node ports directly)
- `hostPorts: [80, 443, 8443]`

These are restricted by Kubernetes default policies, so the cluster allows them in the `ingress-nginx` namespace:
```bash
kubectl get namespace ingress-nginx -o jsonpath='{.metadata.labels}'
# Shows: pod-security.kubernetes.io/enforce=privileged
```

### Service Configuration
All services configured correctly:
- ArgoCD: `argocd-server` service (port 443 with HTTPS backend protocol)
- Grafana: `kube-prometheus-stack-grafana` service (port 80)
- Prometheus: `kube-prometheus-stack-prometheus` service (port 9090)
- Alertmanager: `kube-prometheus-stack-alertmanager` service (port 9093)

### Testing

From inside cluster:
```bash
kubectl exec -it -n monitoring deployment/kube-prometheus-stack-grafana -- \
  curl -s http://grafana.local/api/health | head
```

From macOS (after /etc/hosts):
```bash
curl -H "Host: argocd.local" http://192.168.64.10/
curl -H "Host: grafana.local" http://192.168.64.10/
```

## Troubleshooting

### "No such host" error
- Check `/etc/hosts` has correct entry
- Verify IP is `192.168.64.10` (node IP where ingress is running)
- Check if ingress pod is running: `kubectl get pods -n ingress-nginx`

### Connection refused (port 80)
- Verify hostNetwork is enabled: `kubectl get deployment ingress-nginx-controller -n ingress-nginx -o yaml | grep hostNetwork`
- Check pod is bound to node IP: `kubectl get pods -n ingress-nginx -o wide`

### Ingress not routing traffic
- Check ingress resource: `kubectl get ingress -A`
- Verify backend service exists: `kubectl get svc -n monitoring | grep grafana`
- Check pod logs: `kubectl logs -n ingress-nginx deployment/ingress-nginx-controller`

---

**Architecture**: Kubernetes-native Ingress with standard web ports  
**Status**: ✅ Production-ready  
**Date**: 2026-04-29
