# Getting Started

## Prerequisites

Install tools with Homebrew:

```bash
brew install cirruslabs/cli/tart \
             opentofu \
             siderolabs/tap/talosctl \
             kubectl \
             helm \
             fluxcd/tap/flux
```

## Required Files (one-time setup)

### 1. Talos Disk Image

Download from [factory.talos.dev](https://factory.talos.dev):
- Version: `v1.13.0`
- Platform: `metal`
- Architecture: `arm64`
- Extensions: none

Place it at the path configured in `terraform.tfvars` (default: `~/Downloads/metal-arm64.raw`).

### 2. NVRAM Seed

Tart needs a UEFI NVRAM seed to boot arm64 VMs. Copy from any existing Tart VM:

```bash
cp ~/.tart/vms/<any-vm>/nvram bootstrap/terraform/nvram-arm64.bin
```

Or extract from the repo root if present:

```bash
cp nvram-arm64.bin bootstrap/terraform/nvram-arm64.bin
```

## Deploy

```bash
cd ~/Codes/Personal/tart-lab/Talos-on-macos/bootstrap/terraform

# Copy and edit the example config
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set talos_image_path, github_token, github_owner, github_repo

tofu init
tofu apply
```

Terraform provisions 6 VMs → installs Talos → bootstraps Kubernetes → deploys Cilium → bootstraps Flux → configures DNS and CA trust on macOS.

## Access Services

After `tofu apply` completes, run `setup-dns.sh` (called automatically by Terraform):

```bash
bash setup-dns.sh
```

Then open:
- https://argocd.talos-tart-ha.talos-on-macos.com
- https://grafana.talos-tart-ha.talos-on-macos.com  (admin / change-me)
- https://prometheus.talos-tart-ha.talos-on-macos.com

## Destroy

```bash
tofu destroy
```

Then clean up macOS:

```bash
sudo rm -f /etc/resolver/talos-on-macos.com
sudo dscacheutil -flushcache
```
