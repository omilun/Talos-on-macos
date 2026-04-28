# Terraform Bootstrap — Talos HA Cluster

This directory contains the **Day 0–1** OpenTofu (Terraform) code that provisions a complete Talos Linux HA Kubernetes cluster on macOS from scratch.

Terraform does the minimum to hand off to Flux:

```
tart-vms → talos → cilium → gateway-api-crds → flux
                                                  ↓
                                           (Flux takes over Day 2)
```

---

## What Terraform Manages

| Module | What it does |
|--------|-------------|
| `tart-vms` | Creates 6 Tart VMs with unique MAC addresses; discovers IPs via ARP |
| `talos` | Generates machine secrets, applies configs, bootstraps etcd, writes kubeconfig |
| `cilium` | Installs Cilium v1.19 (eBPF, kube-proxy replacement, Gateway API controller) |
| `gateway-api` | Installs Gateway API CRDs v1.2+ (standard channel) |
| `flux` | Installs Flux controllers; creates `GitRepository` + `Kustomization` |

## What Flux Manages (see `gitops/`)

After `tofu apply` completes, Flux syncs `gitops/clusters/tart-lab/` and installs:

| Component | Helm chart | Namespace |
|-----------|-----------|-----------|
| Networking (GatewayClass, LBPool, Gateway) | — | `networking` |
| cert-manager | `cert-manager v1.20+` | `cert-manager` |
| ArgoCD | `argo-cd v7.9+` | `argocd` |
| kube-prometheus-stack | `kube-prometheus-stack v84+` | `monitoring` |
| Loki (single-binary) | `loki v6.55+` | `monitoring` |
| Promtail | `promtail v6.17+` | `monitoring` |

---

## Prerequisites

```bash
brew install cirruslabs/cli/tart opentofu siderolabs/tap/talosctl kubectl helm fluxcd/tap/flux
```

You also need:
1. A Talos ARM64 disk image — download `metal-arm64.raw` from [factory.talos.dev](https://factory.talos.dev)
2. An `nvram-arm64.bin` UEFI seed file — see [root README](../../README.md#getting-the-nvram-seed)

---

## Usage

```bash
cd bootstrap/terraform

# 1. Copy example vars and edit
cp terraform.tfvars.example terraform.tfvars

# 2. Set your Flux GitOps repo (fork of this repo recommended)
# Edit terraform.tfvars:
#   flux_git_repository_url = "https://github.com/YOUR_USERNAME/Talos-on-macos"

# 3. Init and apply
tofu init
tofu plan    # review ~27 resources
tofu apply

# 4. Use the cluster
export KUBECONFIG=$(tofu output -raw kubeconfig_path)
kubectl get nodes

# 5. Watch Flux reconcile the platform
flux get all -A --watch
```

### Useful outputs

```bash
tofu output kubectl_hint      # export KUBECONFIG=...
tofu output talosctl_hint     # export TALOSCONFIG=...
tofu output flux_hint         # flux get all -A
tofu output etc_hosts_hint    # get Gateway LB IP + hostnames to add
tofu output platform_urls     # all service URLs
```

---

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `talos_version` | `v1.13.0` | Talos Linux release |
| `kubernetes_version` | `1.35.2` | Kubernetes release (no `v` prefix) |
| `cluster_name` | `talos-tart-ha` | Cluster name for kubeconfig context |
| `talos_vip` | `192.168.64.100` | HA VIP for control-plane access from macOS |
| `tart_bridge_gateway` | `192.168.64.1` | Tart `vmnet-shared` bridge gateway — do not change |
| `image_path` | `~/Downloads/metal-arm64.raw` | Talos ARM64 disk image |
| `disk_size_gb` | `20` | VM disk size (GiB) |
| `cp_cpu` | `2` | Control-plane vCPUs |
| `cp_memory_gb` | `4` | Control-plane RAM (GiB) |
| `worker_cpu` | `2` | Worker vCPUs |
| `worker_memory_gb` | `2` | Worker RAM (GiB) — minimum 2 for Loki |
| `gateway_api_version` | `v1.2.1` | Gateway API CRDs version |
| `flux_git_repository_url` | `https://github.com/omilun/Talos-on-macos` | GitOps source |
| `flux_git_branch` | `main` | Branch to sync |
| `flux_git_path` | `gitops/clusters/tart-lab` | Path within repo |
| `flux_github_token` | `""` (sensitive) | GitHub PAT for private repos |

See `variables.tf` for validation rules and `terraform.tfvars.example` for the full list.

---

## Module Details

### `tart-vms`

- Uses `null_resource` + shell provisioners (not the Tart Terraform provider, which doesn't support raw images and custom NVRAM).
- Each VM gets a deterministic MAC address. IPs are discovered from the macOS ARP table after boot.
- `for_each` on the VM map allows independent VM operations.

**Known gotcha**: If a VM's ARP entry is `(incomplete)` at discovery time, the IP returns empty and the route becomes `/32` (invalid). This can happen on the first boot of `talos-cp2`. Fix: stop/restart the VM and re-run `tofu apply`.

### `talos`

- Generates Talos machine secrets (stored in TF state with `prevent_destroy = true`).
- Each node gets a machine config with its peer IP injected as a `/32` static route via the Tart bridge gateway — required because Tart's `vmnet-shared` is a `PRIVATE` bridge (VMs can reach the host, but direct peer-to-peer routing requires this workaround).
- Bootstraps etcd on CP1; polls until the API server is healthy before writing kubeconfig.

### `cilium`

- Installed via shell provisioner using `helm upgrade --install` rather than the Helm Terraform provider — the provider requires static provider config and can't reference dynamic kubeconfig from state.
- Key values: `kubeProxyReplacement=true`, `k8sServiceHost=127.0.0.1` (KubePrism), `k8sServicePort=7445`, `gatewayAPI.enabled=true`, `envoy.enabled=true`.

### `gateway-api`

- Applies the official `standard-install.yaml` CRD bundle from `github.com/kubernetes-sigs/gateway-api`.
- CRDs are never pruned on `tofu destroy` — they are cluster infrastructure shared across workloads.

### `flux`

- Runs `flux install` and `flux create source git` + `flux create kustomization`.
- For public repos, no token is needed. For private repos, set `TF_VAR_flux_github_token`.

---

## Teardown

```bash
tofu destroy
```

> **Talos machine secrets are protected** (`prevent_destroy = true`). If you want a complete teardown including regenerating PKI:
>
> ```bash
> tofu state rm 'module.talos.talos_machine_secrets.this'
> tofu destroy
> ```

---

## Tips

- Run `tofu apply` again if it partially fails — all modules are idempotent.
- State file (`terraform.tfstate`) contains sensitive data (Talos secrets, kubeconfig). Keep it safe — never commit it.
- The `_out/` directory (kubeconfig, talosconfig) is gitignored.

