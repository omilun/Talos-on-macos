# Usage & Operations

Common tasks and workflows for managing your Talos Kubernetes cluster.

## Accessing the Cluster

### Set kubeconfig

```bash
export KUBECONFIG=$(pwd)/../../_out/kubeconfig.yaml
kubectl get nodes
```

Or permanently:

```bash
mkdir -p ~/.kube
cp _out/kubeconfig.yaml ~/.kube/talos-on-macos.yaml
export KUBECONFIG=~/.kube/talos-on-macos.yaml
```

### Check cluster health

```bash
# Nodes
kubectl get nodes -w

# System pods
kubectl get pod -n kube-system
kubectl get pod -n monitoring
kubectl get pod -n flux-system

# Wait for all to be Running
```

---

## Accessing Services

### ArgoCD (Application Delivery UI)

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

Access: **https://localhost:8080**

Credentials:
- Username: `admin`
- Password:
  ```bash
  kubectl get secret -n argocd argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d
  ```

### Prometheus (Metrics)

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Access: **http://localhost:9090**

Query examples:
- `rate(container_cpu_usage_seconds_total[5m])` — CPU usage
- `container_memory_usage_bytes` — Memory
- `up{job="kubelet"}` — Node health

### Grafana (Dashboards)

```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

Access: **http://localhost:3000**

Credentials:
- Username: `admin`
- Password:
  ```bash
  kubectl get secret -n monitoring grafana \
    -o jsonpath='{.data.admin-password}' | base64 -d
  ```

Pre-installed dashboards:
- Kubernetes Cluster Monitoring
- Node Exporter Full
- Loki Dashboard quick search

### Loki (Log Aggregation)

Query via Grafana → Explore → Loki data source.

Example query:
```
{pod="my-app"}
|= "error"
```

Logs from all nodes are aggregated; Promtail ships logs from kubelet, containerd.

---

## Managing Workloads

### Deploy an application via Flux

1. Create a directory in your git repo:

```bash
mkdir -p gitops/apps/my-app
```

2. Create a Kustomization:

```bash
cat > gitops/apps/my-app/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: my-app

resources:
  - deployment.yaml
  - service.yaml
  - gateway-route.yaml
EOF
```

3. Create manifests (deployment.yaml, service.yaml, etc.)

4. Add to the root Kustomization (gitops/kustomization.yaml):

```yaml
resources:
  - ./infrastructure
  - ./apps/my-app
```

5. Commit & push:

```bash
git add gitops/
git commit -m "Add my-app"
git push
```

6. Flux auto-syncs:

```bash
flux reconcile source git flux-system
flux reconcile kustomization flux-system
```

Verify:

```bash
kubectl get deployment -n my-app
kubectl get gateway -n my-app
```

### Add a Helm Release

Instead of kustomize, use HelmRelease for charts:

```bash
mkdir -p gitops/apps/redis
cat > gitops/apps/redis/helmrelease.yaml <<EOF
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: redis
  namespace: redis
spec:
  interval: 5m
  chart:
    spec:
      chart: redis
      version: 18.x  # auto-patch
      sourceRef:
        kind: HelmRepository
        name: bitnami
        namespace: flux-system
  values:
    auth:
      enabled: false
    replica:
      replicaCount: 1
EOF
```

Then add to your root Kustomization resources.

### Update an application

1. Edit its manifest or HelmRelease values in git
2. Commit & push
3. Flux auto-syncs (watch: `kubectl get hr -A`)

### Delete an application

1. Remove from git Kustomization resources
2. Commit & push
3. Flux removes it from cluster

---

## Cluster Maintenance

### Adding more worker nodes

Edit `terraform.tfvars`:

```hcl
worker_count = 5  # (was 3)
```

Apply:

```bash
tofu apply
```

Terraform adds 2 new worker VMs, installs Talos, joins them to cluster.

### Updating Talos

Update `terraform.tfvars`:

```hcl
talos_version = "v1.14.0"  # (was v1.13.0)
```

Also download the new disk image and update `talos_disk_image_path`.

Apply:

```bash
tofu apply
```

Terraform updates machine config and schedules rolling node upgrades.

### Updating Kubernetes

Similarly, update `terraform.tfvars`:

```hcl
kubernetes_version = "v1.36.0"  # (was v1.35.0)
```

Apply:

```bash
tofu apply
```

Talos handles the kubeadm upgrade automatically.

### Scaling down

Reduce VM counts in `terraform.tfvars`, then `tofu apply`. Terraform cordon & drain nodes before deletion.

---

## Node Access

### SSH into a node

First, ensure you have Talos configs:

```bash
export TALOSCONFIG=$(pwd)/../../_out/talosconfig
```

Dashboard (interactive):

```bash
talosctl -n 192.168.64.101 dashboard
```

SSH (if key installed):

```bash
ssh -i <private-key> talos@192.168.64.101
```

### Talos API commands

```bash
# System status
talosctl -n 192.168.64.101 status

# Machine config (live)
talosctl -n 192.168.64.101 get machineconfig

# Logs
talosctl -n 192.168.64.101 logs controller-manager
talosctl -n 192.168.64.101 logs kubelet
talosctl -n 192.168.64.101 logs containerd
```

---

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common issues.

Quick diagnostics:

```bash
# Node status
kubectl get nodes -o wide

# Pod status (all namespaces)
kubectl get pod -A --sort-by=.metadata.creationTimestamp

# Events
kubectl get events -A --sort-by='.lastTimestamp'

# Flux status
flux get all --all-namespaces

# Cilium health
kubectl exec -n kube-system -it <cilium-pod> -- cilium status

# Logs
kubectl logs -n kube-system <pod-name>
```

---

## Managing Multiple Clusters

If you've deployed multiple clusters (e.g., cluster1, cluster2):

### Switching between clusters

```bash
# cluster1
export KUBECONFIG=~/Codes/Personal/tart-lab/Talos-on-macos/clusters/cluster1/_out/kubeconfig.yaml
kubectl get nodes

# cluster2
export KUBECONFIG=~/Codes/Personal/tart-lab/Talos-on-macos/clusters/cluster2/_out/kubeconfig.yaml
kubectl get nodes
```

Or use a kubeconfig merger:

```bash
export KUBECONFIG=\
  ~/Codes/Personal/tart-lab/Talos-on-macos/clusters/cluster1/_out/kubeconfig.yaml:\
  ~/Codes/Personal/tart-lab/Talos-on-macos/clusters/cluster2/_out/kubeconfig.yaml
kubectl config get-contexts
kubectl config use-context <cluster-context>
```

### GitOps per cluster

Each cluster has its own git branch or separate repo. Configure in `terraform.tfvars`:

```hcl
flux_repository_branch = "cluster1-main"  # Different per cluster
```

This way, cluster1 syncs cluster1-main, cluster2 syncs cluster2-dev, etc.

---

## Cleanup

### Destroy a cluster

```bash
cd clusters/cluster1/bootstrap/terraform
tofu destroy
```

Terraform will:
1. Cordon all nodes
2. Delete all Kubernetes resources
3. Power off and delete Tart VMs

### Full cleanup (delete local state)

```bash
rm -rf clusters/cluster1/bootstrap/terraform/.terraform
rm clusters/cluster1/bootstrap/terraform/terraform.tfstate*
rm -rf clusters/cluster1/_out
```

(Backup first if needed!)

---

## Advanced Customization

### Talos patches

Edit `clusters/cluster1/bootstrap/terraform/terraform.tfvars`:

```hcl
talos_patches = {
  controlplane = [
    file("patches/controlplane-patch.yaml")
  ]
  worker = [
    file("patches/worker-patch.yaml")
  ]
}
```

Example patches (kernel, sysctls, mount mounts):

```yaml
# patches/worker-patch.yaml
machine:
  sysctls:
    net.ipv4.ip_forward: "1"
    fs.file-max: "2097152"
```

### GitOps overlays

Use Kustomize overlays for per-cluster customization:

```
gitops/
├── base/                   # shared
│   ├── prometheus/
│   └── loki/
└── overlays/
    ├── cluster1/           # cluster1-specific
    │   ├── kustomization.yaml
    │   └── prometheus-values.yaml
    └── cluster2/           # cluster2-specific
        └── kustomization.yaml
```

Then in Flux Kustomization:

```yaml
apiVersion: kustomize.config.k8s.io/v1
kind: Kustomization
metadata:
  name: apps
spec:
  path: ./gitops/overlays/cluster1
```

---

## Next Steps

- [Architecture deep dive](architecture.md)
- [Terraform reference](../clusters/cluster1/bootstrap/terraform/README.md)
- [GitOps reference](../clusters/cluster1/gitops/README.md)
- [Troubleshooting](troubleshooting.md)
