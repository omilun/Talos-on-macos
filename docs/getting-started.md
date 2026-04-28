# Getting Started

## Installation & Setup

This guide walks you through installing all prerequisites and deploying your first cluster.

### Step 1: Install Tools

Install using Homebrew:

```bash
brew install cirruslabs/cli/tart \
             opentofu \
             siderolabs/tap/talosctl \
             kubectl \
             helm \
             fluxcd/tap/flux
```

Verify installations:

```bash
tart --version
tofu --version
talosctl version
kubectl version --client
helm version
flux version
```

### Step 2: Get the Talos Disk Image

Download from [factory.talos.dev](https://factory.talos.dev):

1. Visit the factory website
2. Select:
   - **Version**: `v1.13.0` (or your preferred version)
   - **Platform**: `metal`
   - **Architecture**: `arm64`
   - **Extensions**: (none — bare metal)
3. Click "Download"
4. Place the image where Terraform expects it:

```bash
mv ~/Downloads/metal-arm64.raw ~/Downloads/metal-arm64.raw
```

(Update the path in `terraform.tfvars` if you place it elsewhere.)

### Step 3: Get the NVRAM Seed

Tart needs a UEFI NVRAM seed file to boot arm64 VMs. Choose one method:

**Method A: Extract from existing Tart VM** (fastest)

If you have any existing Tart VMs:

```bash
ls ~/.tart/vms/
cp ~/.tart/vms/<any-vm-name>/nvram clusters/cluster1/nvram-arm64.bin
```

**Method B: Copy from another project**

If you have another project using Tart:

```bash
cp /path/to/other/project/nvram-arm64.bin clusters/cluster1/
```

**Method C: Create from scratch**

See [Tart documentation](https://tart.run/docs/) for detailed UEFI NVRAM creation steps.

### Step 4: Clone & Configure

```bash
git clone https://github.com/omilun/Talos-on-macos.git
cd Talos-on-macos/clusters/cluster1/bootstrap/terraform
```

Copy the example configuration:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your settings:

```hcl
cluster_name           = "tart-lab"           # Name of your cluster
talos_version          = "v1.13.0"            # Talos version
kubernetes_version     = "v1.35.0"            # Kubernetes version
control_plane_count    = 3                    # Usually 3 for HA
worker_count           = 3                    # Worker nodes
talos_disk_image_path  = "${path.module}/../../../nvram-arm64.bin"  # Path to disk image
nvram_path             = "${path.module}/../../../nvram-arm64.bin"   # Path to NVRAM seed
flux_repository_owner  = "omilun"             # Your GitHub username
flux_repository_name   = "Talos-on-macos"     # Your fork of this repo
```

Key settings:

| Variable | Description |
|----------|-------------|
| `cluster_name` | Used for VM names, Talos machine names, and in kubeconfig |
| `talos_version` | Talos Linux version; must match your disk image |
| `kubernetes_version` | Kubernetes version; Talos will use this for kubeadm |
| `control_plane_count` / `worker_count` | Number of VMs (1 CP + 1 worker = minimal; 3+3 = HA) |
| `talos_disk_image_path` | Path to downloaded `metal-arm64.raw` |
| `nvram_path` | Path to extracted/copied `nvram-arm64.bin` |
| `flux_repository_owner`, `flux_repository_name` | Your fork of this repo (for GitOps sync) |

### Step 5: Deploy

Initialize Terraform:

```bash
tofu init
```

Preview the plan:

```bash
tofu plan
```

Apply:

```bash
tofu apply
```

This takes **5–10 minutes**. Terraform will:
1. Create VMs and configure Talos
2. Bootstrap the Kubernetes cluster
3. Install Cilium, Gateway API, and cert-manager
4. Bootstrap Flux to manage the rest

### Step 6: Access Your Cluster

After `tofu apply` completes, set up kubectl:

```bash
export KUBECONFIG=$(pwd)/../../_out/kubeconfig.yaml
kubectl get nodes
```

You should see 6 nodes (3 control-plane, 3 workers).

Check cluster health:

```bash
kubectl get pod -A
```

Wait for all pods to be Running.

### Step 7: Access Services

#### ArgoCD (Application Delivery)

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
# https://localhost:8080
# Username: admin
# Password: (check the argocd-initial-admin-secret)
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

#### Prometheus (Metrics)

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# http://localhost:9090
```

#### Grafana (Dashboards)

```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
# http://localhost:3000
# Username: admin
# Password: (check grafana secret)
kubectl get secret -n monitoring grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

---

## Troubleshooting

### SSH into a node

```bash
talosctl -n 192.168.64.101 dashboard
# or
ssh -i <generated-key> talos@192.168.64.101
```

### Check Talos logs

```bash
export TALOSCONFIG=$(pwd)/../../_out/talosconfig
talosctl -n 192.168.64.101 logs controller-manager
```

### Kubernetes logs

```bash
kubectl logs -n kube-system -l component=kubelet
```

### Flux reconciliation

```bash
flux get kustomization
flux get helmrelease -A
```

For more, see [troubleshooting.md](troubleshooting.md).

---

## What's Next?

- **[Customization](usage.md#customization)** — Adding apps, modifying GitOps manifests
- **[Multi-cluster setup](../README.md#multi-cluster-setup)** — Deploying additional clusters
- **[Architecture deep dive](architecture.md)** — Understanding the design
- **[Terraform reference](../clusters/cluster1/bootstrap/terraform/README.md)** — All provisioning options
