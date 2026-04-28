# Cluster1 Configuration

This directory contains the complete configuration for **cluster1** — the primary example cluster.

## Structure

```
cluster1/
├── bootstrap/              # Day 0–1 provisioning
│   └── terraform/          # OpenTofu infrastructure
├── gitops/                 # Day 2+ declarative operations
│   ├── apps/               # Application workloads
│   ├── infrastructure/     # Platform stack (Cilium, cert-manager, etc.)
│   ├── clusters/           # Cluster-specific Flux Kustomizations
│   └── README.md           # GitOps structure docs
├── k8s-v1.32/             # (optional) Kubernetes v1.32-specific overrides
└── README.md              # This file
```

## Quick Start

### 1. Deploy the cluster

```bash
cd bootstrap/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
tofu apply
```

This takes 5–10 minutes and provisions:
- 6 Tart VMs (3 control-plane, 3 workers)
- Talos Linux
- Kubernetes cluster
- Cilium CNI
- Gateway API
- Flux bootstrap

### 2. Access the cluster

```bash
export KUBECONFIG=$(pwd)/../../_out/kubeconfig.yaml
kubectl get nodes
```

### 3. Wait for platform stack to be ready

```bash
kubectl get pod -A
# Wait for all pods to be Running
```

Then access services (ArgoCD, Prometheus, Grafana) via `kubectl port-forward`.

## Configuration

All provisioning settings are in `bootstrap/terraform/terraform.tfvars`.

Key variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `cluster_name` | Cluster name (affects VM names, kubeconfig) | `tart-lab` |
| `talos_version` | Talos Linux version | `v1.13.0` |
| `kubernetes_version` | Kubernetes version (kubeadm) | `v1.35.0` |
| `control_plane_count` | Number of control-plane nodes | `3` |
| `worker_count` | Number of worker nodes | `3` |
| `talos_disk_image_path` | Path to metal-arm64.raw | `~/Downloads/metal-arm64.raw` |
| `nvram_path` | Path to nvram-arm64.bin seed | `./nvram-arm64.bin` |
| `flux_repository_owner` | GitHub username (for GitOps sync) | `omilun` |
| `flux_repository_name` | GitHub repo name | `Talos-on-macos` |
| `flux_repository_branch` | Git branch to sync | `main` |

See [bootstrap/terraform/README.md](bootstrap/terraform/README.md) for all variables.

## Customization

### Update Talos patches

Edit `bootstrap/terraform/variables.tf` or add Talos machine config patches:

```hcl
# In terraform.tfvars
talos_patches = {
  controlplane = [
    file("patches/controlplane-patch.yaml")
  ]
  worker = [
    file("patches/worker-patch.yaml")
  ]
}
```

Example patch (`patches/worker-patch.yaml`):

```yaml
machine:
  sysctls:
    net.ipv4.ip_forward: "1"
  install:
    extraKernelArgs:
      - talos.logging.kernel=debug
```

### Update GitOps applications

Edit manifests in `gitops/`:

```bash
# Add a new app
mkdir -p gitops/apps/my-app
cat > gitops/apps/my-app/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: my-app
resources:
  - deployment.yaml
  - service.yaml
EOF

# Create deployment.yaml, service.yaml, etc.

# Update root Kustomization
# gitops/kustomization.yaml
# Add: - ./apps/my-app to resources list

git add gitops/
git commit -m "Add my-app"
git push
```

Flux auto-syncs on git push.

### Scale up/down

```bash
# Edit terraform.tfvars
control_plane_count = 5  # increase control-plane
worker_count = 10        # increase workers

tofu apply
```

Terraform will add/remove VMs and join/drain from cluster.

### Update Kubernetes version

```bash
# Download new Talos image from factory.talos.dev
# Update terraform.tfvars
talos_version = "v1.14.0"
kubernetes_version = "v1.36.0"
talos_disk_image_path = "~/Downloads/metal-arm64-v1.14.0.raw"

tofu apply
```

Talos will schedule rolling updates.

## Destroying the cluster

```bash
cd bootstrap/terraform
tofu destroy
```

This will:
1. Cordon all Kubernetes nodes
2. Delete all Kubernetes resources
3. Power off and delete Tart VMs
4. Clean up networking

**Note**: Terraform state is kept. To fully reset:

```bash
rm -rf bootstrap/terraform/.terraform
rm bootstrap/terraform/terraform.tfstate*
rm -rf _out
```

## Multi-cluster setup

If you've deployed multiple clusters (cluster1, cluster2, etc.):

```bash
# Switch between clusters
export KUBECONFIG=~/path/to/cluster1/_out/kubeconfig.yaml
kubectl get nodes

export KUBECONFIG=~/path/to/cluster2/_out/kubeconfig.yaml
kubectl get nodes
```

Each cluster is independent and can be customized separately.

## Kubernetes version variants

This directory supports Kubernetes version-specific configurations:

```
cluster1/
├── bootstrap/terraform/        # Default (v1.35.0)
└── k8s-v1.32/                  # v1.32-specific overrides
    ├── patches/
    ├── terraform.tfvars.override
    └── README.md
```

To deploy v1.32 variant:

```bash
cd k8s-v1.32/
cp terraform.tfvars.example terraform.tfvars
# Terraform includes parent values, overrides are merged
tofu apply
```

(Coming in v2: parameterized Terraform modules for cleaner variant support.)

## Documentation

- [Bootstrap Terraform README](bootstrap/terraform/README.md) — Provisioning reference
- [GitOps README](gitops/README.md) — Declarative operations structure
- [Getting Started](../../docs/getting-started.md) — Detailed walkthrough
- [Architecture](../../docs/architecture.md) — Design deep dive
- [Usage](../../docs/usage.md) — Common operations
- [Troubleshooting](../../docs/troubleshooting.md) — Problem solving

## Next Steps

1. [Getting Started](../../docs/getting-started.md) — Install prerequisites, deploy cluster
2. [Usage](../../docs/usage.md) — Access services, add applications
3. [Troubleshooting](../../docs/troubleshooting.md) — Solve common problems

---

**Happy clustering!** 🚀
