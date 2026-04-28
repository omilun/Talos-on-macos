# Troubleshooting: Ingress Access Issues

## Problem
ArgoCD and other services are deployed and running inside the cluster, but they are not accessible from the macOS host at `https://argocd.local` or other configured hostnames.

## Symptoms
- `curl https://argocd.local` times out or connection refused
- Ping to VIP (192.168.64.192 or similar) returns no response
- Services work when accessed from inside cluster pods
- `kubectl port-forward` returns "error upgrading connection"

## Root Causes

### 1. Cilium Gateway API Incomplete Implementation
**Status**: Not suitable for this environment

Cilium's Gateway API support creates `Gateway` and `HTTPRoute` resources but **does not actually proxy external traffic**. The implementation:
- Creates a LoadBalancer service with no endpoint selectors
- Relies on Cilium Envoy sidecars (only expose metrics, not traffic)
- Works for internal service-to-service routing, not external ingress

**Not a viable solution** for exposing services to the macOS host.

### 2. Cilium LoadBalancer IP Allocation (DSR Mode)
**Status**: Not accessible from host

When DSR (Direct Server Return) mode is enabled:
- VIPs are allocated (e.g., 192.168.64.192)
- VIPs are not reachable via ping or TCP connection
- Likely due to Tart's virtual network bridge topology not supporting DSR

**Root cause**: DSR requires traffic to return directly from pods to client without going through the LoadBalancer node. Tart's network doesn't support this path.

### 3. Talos Kubelet TLS Configuration Error
**Status**: Blocks debugging and alternative solutions

Error signature:
```
remote error: tls: internal error
```

Affects:
- `kubectl exec` into pods
- `kubectl logs` retrieval
- `kubectl port-forward` to services
- Any kubelet communication requiring TLS

**Impact**: Cannot use standard Kubernetes access methods to reach services even via port-forward tunnels.

## Solutions

### Option 1: Fix Cilium SNAT Mode (Recommended for Tart)
Replace DSR with SNAT (Source NAT) mode:
```bash
helm upgrade cilium cilium/cilium -n kube-system \
  --reuse-values \
  --set loadBalancer.mode=snat \
  --set loadBalancer.algorithm=maglev
```

SNAT mode ensures return traffic goes through the LoadBalancer node, compatible with Tart's network topology.

### Option 2: Use MetalLB Instead of Cilium
MetalLB is more reliable for virtual network environments:
```bash
helm repo add metallb https://metallb.universe.tf
helm install metallb metallb/metallb -n metallb-system --create-namespace
```

Then create an `IPAddressPool`:
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - 192.168.64.100-192.168.64.110
```

### Option 3: Use NGINX Ingress with NodePort
Simpler alternative that works with Tart:
```bash
helm install nginx-ingress nginx-stable/nginx-ingress \
  -n ingress-nginx --create-namespace \
  --set controller.service.type=NodePort
```

Access via node IP and port:
```bash
kubectl get svc -n ingress-nginx nginx-ingress-controller
# Use the reported NodePort for https (e.g., 31960)
curl -k https://192.168.64.6:31960 -H "Host: argocd.local"
```

### Option 4: Temporary Workaround - Direct Service Access
While solving the ingress issue, access services internally via:
```bash
# Get ArgoCD password
export ARGO_PASSWD=$(kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# Access via kubectl proxy (requires working kubelet TLS)
kubectl proxy &
curl http://localhost:8001/api/v1/namespaces/argocd/pods/proxy/argocd-server
```

**Note**: Requires fixing Talos kubelet TLS first.

## Fix Talos Kubelet TLS

This requires accessing the Talos control plane to regenerate kubelet certificates:

```bash
# Get Talos API access
talosctl config endpoint 192.168.64.6
talosctl config node 192.168.64.6

# Regenerate kubelet certificate
talosctl gen certs -o /tmp/certs

# Apply to cluster
talosctl apply-config --insecure --nodes 192.168.64.6 -f <config-file>
```

Or restart kubelet service on all nodes:
```bash
for ip in 192.168.64.{6..11}; do
  talosctl reboot --nodes $ip
done
```

## Verification Steps

1. **Verify Cilium configuration**:
   ```bash
   kubectl get daemonset -n kube-system cilium -o yaml | grep loadBalancer
   ```

2. **Check LoadBalancer service status**:
   ```bash
   kubectl get svc ingress-controller
   kubectl get endpoints ingress-controller
   ```

3. **Test from a cluster pod**:
   ```bash
   kubectl run test --image=curlimages/curl -it -- curl https://argocd-server.argocd:443
   ```

4. **Verify ingress configuration**:
   ```bash
   kubectl get ingress -A
   kubectl describe ingress argocd -n argocd
   ```

## Current Status

| Component | Status | Issue |
|-----------|--------|-------|
| Services (ArgoCD, Prometheus, etc.) | ✅ Running | None - all pods operational |
| Kubernetes cluster | ✅ Ready | None - 6 nodes healthy |
| Cilium networking | ✅ Active | Can't expose LoadBalancer outside cluster |
| Ingress controller | ❌ Partial | TLS issues prevent debugging |
| Kubelet TLS | ❌ Broken | Affects pod access and logs |

## Related Documentation
- See `docs/architecture.md` for Gateway API design decisions
- See `docs/usage.md` for accessing services
- See `STRUCTURE.md` for cluster configuration paths
