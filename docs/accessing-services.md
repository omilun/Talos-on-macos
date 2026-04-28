# Accessing Services

This guide explains how to access ArgoCD and other platform services running in your Talos cluster.

## Quick Start

### ArgoCD Dashboard

**Direct URL**: `http://192.168.64.6:32232`

**Credentials**:
```
Username: admin
Password: rQwuRbjDeHtXkImn
```

### Other Services

Services are accessible on the following nodes:
- **Primary control-plane node**: 192.168.64.6
- **Other control-plane nodes**: 192.168.64.7, 192.168.64.8
- **Worker nodes**: 192.168.64.9, 192.168.64.10, 192.168.64.11

## Service Access Methods

### Method 1: Direct NodePort (Recommended for Tart)

All services are exposed as NodePort services. Access them directly on any node:

```bash
# ArgoCD
curl http://192.168.64.6:32232

# Get all available NodePorts
kubectl get svc -A | grep NodePort
```

### Method 2: Via Hostname (Requires DNS Update)

To access services by hostname instead of IP, update `/etc/hosts`:

```bash
# Edit /etc/hosts and replace the 127.0.0.1 entry with your node IP:
192.168.64.6 argocd.local grafana.local prometheus.local alertmanager.local
```

Then access:
```bash
curl http://argocd.local:32232
```

### Method 3: Kubernetes Proxy (Requires Working Kubelet TLS)

If kubelet TLS is fixed, use kubectl proxy:

```bash
kubectl proxy &
# Access services via
http://localhost:8001/api/v1/namespaces/argocd/services/argocd-server:443/proxy/
```

## Service Ports

To find the NodePort for any service:

```bash
# List all services
kubectl get svc -A -o wide | grep NodePort

# Get specific service port
kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}'
```

## Why NodePort Instead of LoadBalancer?

The Talos-on-Tart environment uses virtual networking that has specific limitations:

1. **Cilium Gateway API** doesn't work for external ingress (internal service mesh only)
2. **Cilium LoadBalancer DSR mode** VIPs are not reachable from the macOS host
3. **Cilium LoadBalancer SNAT mode** requires proper network routing configuration

**NodePort is the most reliable method** for Tart virtual networks:
- Directly accessible on node IPs
- No virtual IP routing required
- Works with Tart's network bridge topology
- Standard Kubernetes approach

## Accessing Multiple Services

Create a helper function for quick access:

```bash
# Add to ~/.zshrc or ~/.bashrc
talos-service() {
  local service=$1
  local ns=${2:-default}
  local port=$(kubectl get svc $service -n $ns -o jsonpath='{.spec.ports[0].nodePort}')
  echo "http://192.168.64.6:$port"
}

# Usage
talos-service argocd-server argocd
```

## Troubleshooting Access Issues

### Port Connection Refused
- Verify the NodePort is assigned: `kubectl get svc -n argocd argocd-server`
- Check if the pod is running: `kubectl get pods -n argocd`

### TLS Certificate Warnings
- ArgoCD uses self-signed certificates
- Ignore browser warnings or use `curl -k` flag

### Service Not Responding
- Check service endpoints: `kubectl get endpoints -n <namespace>`
- Verify pod logs (if kubelet TLS is fixed): `kubectl logs -n <namespace> <pod-name>`

## Future Improvements

Once the infrastructure is stabilized, consider:

1. **HTTPS via cert-manager**: Currently configured but requires working ingress
2. **MetalLB for proper LoadBalancer IPs**: Better than NodePort for production
3. **Cilium SNAT mode tuning**: May work once network routing is optimized
4. **Cilium Gateway API**: Once kubelet TLS is fixed and Gateway implementation improved

For now, **NodePort is the recommended approach** for Tart environments.
