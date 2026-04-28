# Repository Structure

This document outlines the multi-cluster, modular structure of the Talos-on-macOS project.

## Directory Layout

```
Talos-on-macos/
├── README.md                                # Project overview & quick links
├── CONTRIBUTING.md                          # Contributing guidelines
├── LICENSE                                  # MIT license
│
├── docs/                                    # Public documentation (modular)
│   ├── getting-started.md                   # Installation & step-by-step guide
│   ├── architecture.md                      # Design & component stack
│   ├── usage.md                             # Common operations & workflows
│   └── troubleshooting.md                   # Problem solving guide
│
├── clusters/                                # Multi-cluster configurations
│   ├── cluster1/                            # Primary example cluster
│   │   ├── README.md                        # Cluster1 setup & customization
│   │   ├── bootstrap/
│   │   │   └── terraform/                   # Day 0–1 provisioning (OpenTofu)
│   │   │       ├── README.md                # Terraform reference
│   │   │       ├── main.tf, outputs.tf, variables.tf, versions.tf
│   │   │       ├── modules/
│   │   │       │   ├── tart-vms/            # VM creation & configuration
│   │   │       │   ├── talos/               # Talos Linux bootstrap
│   │   │       │   ├── cilium/              # CNI installation
│   │   │       │   ├── gateway-api/         # Gateway API CRDs
│   │   │       │   └── flux/                # Flux bootstrap
│   │   │       ├── terraform.tfvars.example # Configuration template
│   │   │       └── patches/                 # Talos machine config patches
│   │   │
│   │   ├── gitops/                          # Day 2+ declarative operations
│   │   │   ├── README.md                    # GitOps structure docs
│   │   │   ├── infrastructure.yaml          # Kustomization for platform stack
│   │   │   ├── apps.yaml                    # Kustomization for apps
│   │   │   └── ... (actual manifests synced from separate git location)
│   │   │
│   │   ├── k8s-v1.32/                       # Kubernetes v1.32-specific overrides
│   │   │   ├── terraform.tfvars.override
│   │   │   └── patches/
│   │   │
│   │   ├── nvram-arm64.bin                  # UEFI NVRAM seed (gitignored in _out/)
│   │   └── _out/                            # Generated artifacts
│   │       ├── kubeconfig.yaml
│   │       └── talosconfig
│   │
│   ├── cluster2/                            # Additional cluster (template)
│   │   ├── README.md                        # Setup for cluster2
│   │   └── bootstrap/
│   │       └── terraform/                   # Independent provisioning config
│   │
│   └── cluster3/                            # ... more clusters as needed
│
├── bootstrap/                               # (Legacy) Day 0–1 provisioning
│   └── terraform/                           # Original single-cluster setup
│                                             # Kept for backward compatibility
│
├── gitops/                                  # (Legacy) Day 2+ manifests
│   ├── clusters/
│   │   └── tart-lab/                        # Original cluster Kustomizations
│   ├── infrastructure/                      # Platform stack definitions
│   ├── apps/                                # Application workloads
│   └── ... (detailed in gitops/README.md)
│
├── patches/                                 # Shared Talos machine config patches
│   ├── common-patch.yaml
│   ├── controlplane-patch.yaml
│   └── worker-patch.yaml
│
├── nvram-arm64.bin                          # UEFI NVRAM seed (shared)
└── STRUCTURE.md                             # This file
```

## Multi-Cluster Architecture

### cluster1 (Primary Example)

- **Location**: `clusters/cluster1/`
- **Purpose**: Example production-like cluster with full platform stack
- **Components**: 6 Tart VMs (3 CP, 3 workers), Talos, Cilium, Flux, observability stack
- **Customization**: Edit `clusters/cluster1/bootstrap/terraform/terraform.tfvars`

### cluster2 (Template)

- **Location**: `clusters/cluster2/`
- **Purpose**: Template for deploying additional clusters
- **Setup**: Copy from cluster1, update `terraform.tfvars`
- **Independence**: Separate VMs, network, kubeconfig, Git sync

### Additional Clusters

Create as many as needed by copying cluster1:

```bash
cp -r clusters/cluster1 clusters/staging
cp -r clusters/cluster1 clusters/dev
```

Each cluster:
- Has independent VM networking
- Syncs from separate Git branches/repos (via `flux_repository_branch`)
- Maintains its own kubeconfig and state

## Kubernetes Version Variants

Each cluster supports multiple Kubernetes versions:

```
clusters/cluster1/
├── bootstrap/terraform/          # Default (v1.35.0)
└── k8s-v1.32/                    # v1.32-specific configuration
    ├── terraform.tfvars.override # Overrides (merged with defaults)
    └── patches/                  # Version-specific Talos patches
```

Future: Parameterized Terraform modules for cleaner variant management.

## Documentation Hierarchy

1. **Main README.md** — Project overview, quick links, multi-cluster intro
2. **docs/getting-started.md** — Step-by-step installation
3. **docs/architecture.md** — Design deep dive
4. **docs/usage.md** — Common operations
5. **docs/troubleshooting.md** — Problem solving
6. **clusters/cluster1/README.md** — Cluster1 customization
7. **clusters/cluster1/bootstrap/terraform/README.md** — Terraform variables
8. **clusters/cluster1/gitops/README.md** — GitOps structure

## Day 0–1 vs Day 2+

### Day 0–1: Infrastructure Bootstrap (OpenTofu)

**Owner**: `clusters/cluster{N}/bootstrap/terraform/`

Terraform provisions:
1. Tart VMs (6 per cluster)
2. Talos Linux OS
3. Kubernetes cluster
4. Cilium CNI
5. Gateway API CRDs
6. Flux bootstrap

### Day 2+: Declarative Operations (Flux)

**Owner**: `clusters/cluster{N}/gitops/`

Flux manages:
- cert-manager
- ArgoCD
- Prometheus, Grafana, Loki
- User applications
- Any infrastructure changes via git

## Legacy Structure

The original `bootstrap/` and `gitops/` directories at repo root are kept for backward compatibility but should not be used for new deployments. Use `clusters/cluster{N}/` instead.

## State Management

### Terraform State

- **Location**: `clusters/cluster{N}/bootstrap/terraform/terraform.tfstate`
- **Gitignored**: Yes (sensitive data)
- **Backup**: `terraform.tfstate.backup`

Regenerating state:

```bash
cd clusters/cluster{N}/bootstrap/terraform
tofu init
# Terraform will recover state from backend if configured
```

### Kubeconfig

- **Location**: `clusters/cluster{N}/_out/kubeconfig.yaml`
- **Gitignored**: Yes (contains secrets)

Regenerating:

```bash
export KUBECONFIG=clusters/cluster{N}/_out/kubeconfig.yaml
tofu taint null_resource.kubeconfig
tofu apply
```

## Adding a New Cluster

```bash
# 1. Copy from existing cluster
cp -r clusters/cluster1 clusters/cluster-staging

# 2. Navigate to new cluster
cd clusters/cluster-staging/bootstrap/terraform

# 3. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit: change cluster_name, flux_repository_branch (if multi-repo GitOps)

# 4. Deploy
tofu init
tofu apply

# 5. Verify
export KUBECONFIG=$(pwd)/../../_out/kubeconfig.yaml
kubectl get nodes
```

## Adding a Kubernetes Version Variant

```bash
# 1. Create directory
mkdir -p clusters/cluster1/k8s-v1.32

# 2. Add version-specific config
cat > clusters/cluster1/k8s-v1.32/terraform.tfvars.override << 'EOF'
kubernetes_version = "v1.32.0"
talos_version = "v1.13.0"  # adjust if needed
talos_disk_image_path = "~/Downloads/metal-arm64-v1.32.raw"
EOF

# 3. Deploy (Terraform merges base + override)
cd clusters/cluster1/k8s-v1.32
tofu apply -var-file=terraform.tfvars.override
```

## Best Practices

1. **Per-cluster customization**: Never edit files outside `clusters/cluster{N}/`; use `terraform.tfvars` for config
2. **GitOps branches**: Use separate branches for each cluster (e.g., `cluster1-prod`, `cluster2-dev`)
3. **State files**: Back up `terraform.tfstate` files regularly
4. **Documentation**: Update cluster-specific READMEs when making changes
5. **Versioning**: Track Kubernetes, Talos, and tool versions in `terraform.tfvars`

## Next Steps

- [Getting Started](docs/getting-started.md) — Deploy your first cluster
- [Usage](docs/usage.md) — Manage clusters
- [Architecture](docs/architecture.md) — Understand the design
