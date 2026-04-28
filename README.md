# Talos on macOS

> A **production-like**, fully-automated Talos Linux HA Kubernetes cluster running locally on macOS Apple Silicon — provisioned end-to-end with OpenTofu (Terraform) and managed Day-2 with Flux GitOps.

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Talos](https://img.shields.io/badge/Talos-v1.13-FF6B6B?logo=linux&logoColor=white)](https://talos.dev)
[![Cilium](https://img.shields.io/badge/Cilium-v1.19-F8C517?logo=cilium&logoColor=black)](https://cilium.io)
[![Flux](https://img.shields.io/badge/Flux-GitOps-5468FF?logo=flux&logoColor=white)](https://fluxcd.io)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-IaC-7B42BC?logo=terraform&logoColor=white)](https://opentofu.org)
[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-000000?logo=apple&logoColor=white)](https://tart.run)

---

## What is this?

This project gives you a **real Kubernetes cluster** on your MacBook — no cloud, no Docker Desktop, no kind. It's a 6-node HA cluster (3 control-plane + 3 workers) running [Talos Linux](https://talos.dev) inside [Tart](https://tart.run) VMs, with a complete platform stack wired together and managed as code.

**One command** provisions everything:

```
tofu apply
```

That single command: creates 6 VMs → installs Talos → bootstraps etcd → installs Cilium → applies Gateway API CRDs → bootstraps Flux, which then installs cert-manager, ArgoCD, Prometheus, Grafana, Loki, and Promtail — all in the right order, fully declarative.

---

## Architecture

```
macOS Apple Silicon
│
└─ Tart (lightweight ARM64 VMs)
   ├─ talos-cp1  ─┐
   ├─ talos-cp2  ─┼─ HA control-plane (VIP: 192.168.64.100)
   ├─ talos-cp3  ─┘
   ├─ talos-w1   ─┐
   ├─ talos-w2   ─┼─ workers
   └─ talos-w3   ─┘
      │
      └─ Kubernetes platform (Flux-managed)
         ├─ Cilium v1.19          CNI + kube-proxy replacement + Gateway API
         ├─ Gateway API           HTTPRoutes → cilium class
         ├─ cert-manager          self-signed wildcard TLS (ACME-ready)
         ├─ ArgoCD                app delivery  →  https://argocd.local
         ├─ Prometheus            metrics       →  https://prometheus.local
         ├─ Grafana               dashboards    →  https://grafana.local
         ├─ Alertmanager                        →  https://alertmanager.local
         └─ Loki + Promtail       log aggregation (all 6 nodes)
```

### Two-layer design

| Layer | Tool | Responsibility |
|-------|------|---------------|
| **Day 0–1** | OpenTofu | VMs, Talos, Cilium, Gateway API CRDs, Flux bootstrap |
| **Day 2+** | Flux GitOps | Every Helm chart and Kubernetes resource after bootstrap |

Terraform does the minimum necessary to bring Flux up. Everything else is a GitOps concern — adding a new service means opening a PR, not running `helm install`.

---

## Prerequisites

Install all tools with Homebrew:

```bash
brew install cirruslabs/cli/tart \
             opentofu \
             siderolabs/tap/talosctl \
             kubectl \
             helm \
             fluxcd/tap/flux
```

| Tool | Min version | Purpose |
|------|-------------|---------|
| [Tart](https://tart.run) | latest | lightweight Apple Silicon VMs |
| [OpenTofu](https://opentofu.org) | ≥ 1.8 | infrastructure provisioning |
| [talosctl](https://talos.dev) | ≥ 1.13 | Talos API client |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | ≥ 1.28 | Kubernetes CLI |
| [Helm](https://helm.sh) | ≥ 3.14 | used by provisioning scripts |
| [flux CLI](https://fluxcd.io/flux/installation/) | ≥ 2.4 | Flux status + reconciliation |

**Also required:**

- A Talos ARM64 disk image (`metal-arm64.raw`) — download from [factory.talos.dev](https://factory.talos.dev) (choose Talos version + `metal` platform + `arm64`)
- An `nvram-arm64.bin` UEFI seed file — see [Getting the NVRAM seed](#getting-the-nvram-seed)

---

## Quick Start

### 1 — Fork or clone this repo

> If you want Flux to sync your own cluster manifests, **fork** this repo first so you can commit changes to it.

```bash
git clone https://github.com/omilun/Talos-on-macos.git
cd Talos-on-macos
```

### 2 — Get the Talos disk image

Download from [factory.talos.dev](https://factory.talos.dev):
- Version: `v1.13.0`
- Platform: `metal`
- Architecture: `arm64`
- Extension: (none — bare metal)

```bash
# The default variable expects the image here:
mv ~/Downloads/metal-arm64.raw ~/Downloads/metal-arm64.raw
```

### 3 — Get the NVRAM seed

Tart needs an UEFI NVRAM seed file to boot arm64 VMs from raw disk images.

```bash
# Extract from an existing Tart VM, or copy from another project:
cp /path/to/existing/nvram-arm64.bin bootstrap/terraform/
```

> See [Getting the NVRAM seed](#getting-the-nvram-seed) for how to create one from scratch.

### 4 — Configure

```bash
cd bootstrap/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` — at minimum set your `flux_git_repository_url` to your fork:

```hcl
flux_git_repository_url = "https://github.com/YOUR_USERNAME/Talos-on-macos"
```

All other defaults work out of the box on a Mac with Tart's default `vmnet-shared` bridge (`192.168.64.0/24`).

### 5 — Provision

```bash
tofu init
tofu apply
```

This takes **5–10 minutes**. Terraform prints progress. When it finishes:

```bash
# Use the cluster
export KUBECONFIG=$(tofu output -raw kubeconfig_path)
kubectl get nodes

# Watch Flux reconcile the platform stack
export TALOSCONFIG=$(tofu output -raw talosconfig_path)
flux get all -A --watch
```

### 6 — Access the UIs

Get the Gateway LoadBalancer IP (assigned by Cilium's L2 announcements):

```bash
kubectl get gateway main-gateway -n networking \
  -o jsonpath='{.status.addresses[0].value}'
```

Add to `/etc/hosts` (replace `GATEWAY_IP` with the output above):

```bash
sudo tee -a /etc/hosts << EOF
GATEWAY_IP  argocd.local
GATEWAY_IP  grafana.local
GATEWAY_IP  prometheus.local
GATEWAY_IP  alertmanager.local
EOF
```

| Service | URL | Default credentials |
|---------|-----|-------------------|
| ArgoCD | https://argocd.local | `admin` / see note below |
| Grafana | https://grafana.local | `admin` / `change-me` |
| Prometheus | https://prometheus.local | — |
| Alertmanager | https://alertmanager.local | — |

> **ArgoCD password** (auto-generated on first install):
> ```bash
> kubectl get secret argocd-initial-admin-secret -n argocd \
>   -o jsonpath='{.data.password}' | base64 -d
> ```

TLS uses a self-signed root CA — your browser will warn on first visit. Accept the certificate or add the CA to your keychain (see [Trusting the CA](#trusting-the-self-signed-ca)).

---

## Directory Structure

```
.
├── README.md                       ← you are here
├── bootstrap/
│   └── terraform/                  ← Day 0–1: full cluster provisioning
│       ├── README.md               ← Terraform-specific docs
│       ├── main.tf                 ← module orchestration
│       ├── variables.tf            ← all inputs with validation
│       ├── outputs.tf              ← IPs, URLs, CLI hints
│       ├── terraform.tfvars.example
│       └── modules/
│           ├── tart-vms/           ← create/destroy Tart VMs via shell
│           ├── talos/              ← machine secrets, configs, bootstrap
│           ├── cilium/             ← Cilium Helm (eBPF + Gateway API)
│           ├── gateway-api/        ← Gateway API CRD standard channel
│           └── flux/               ← Flux controllers + GitRepository
├── gitops/                         ← Day 2+: Flux-managed platform
│   ├── README.md                   ← GitOps-specific docs
│   ├── clusters/tart-lab/          ← Flux entrypoint Kustomizations
│   │   ├── infrastructure.yaml     ← infrastructure + infrastructure-config
│   │   └── apps.yaml               ← apps (depends on infrastructure)
│   ├── infrastructure/
│   │   ├── sources/                ← HelmRepository declarations
│   │   ├── networking/             ← GatewayClass, LBIPPool, L2 policy, Gateway
│   │   ├── cert-manager/           ← cert-manager Helm + namespace
│   │   ├── cert-manager-config/    ← ClusterIssuers + wildcard cert (after CRDs)
│   │   ├── argocd/                 ← ArgoCD Helm + HTTPRoute
│   │   └── monitoring/             ← kube-prometheus-stack, Loki, Promtail
│   └── apps/                       ← your applications go here
└── patches/                        ← Talos machine config patches
    ├── common-patch.yaml
    ├── controlplane-patch.yaml
    └── worker-patch.yaml
```

---

## How It Works

### Day 0–1: Terraform bootstraps the cluster

```
tart-vms  →  talos  →  cilium  →  gateway-api  →  flux
```

Each Terraform module is independent and uses shell provisioners rather than opinionated Kubernetes providers. This avoids provider version-lock and lets the scripts handle the real-world timing issues that declarative providers struggle with (Talos bootstrap race, ARP discovery, etc.).

### Day 2+: Flux manages everything else

Once Terraform completes, Flux is running and watching this repo. Changes to `gitops/` are reconciled automatically:

```
gitops/clusters/tart-lab/
├── infrastructure.yaml        ← applies infrastructure/ (wait: true)
│     ├── sources              ← HelmRepository objects
│     ├── networking           ← Gateway, Cilium LB pool
│     ├── cert-manager         ← Helm install
│     ├── argocd               ← Helm install
│     └── monitoring           ← Helm install
├── infrastructure.yaml        ← also applies infrastructure-config/
│     └── cert-manager-config  ← ClusterIssuers (after cert-manager CRDs exist)
└── apps.yaml                  ← your apps (after infrastructure is ready)
```

The `infrastructure-config` Kustomization exists to solve a chicken-and-egg problem: `ClusterIssuer` resources require cert-manager CRDs, which are only available _after_ the cert-manager HelmRelease is deployed. By splitting into two Kustomizations with `dependsOn`, Flux handles this correctly.

---

## Customisation

### Change VM sizes

Edit `bootstrap/terraform/terraform.tfvars`:

```hcl
cp_cpu        = 4
cp_memory_gb  = 8
worker_cpu    = 4
worker_memory_gb = 4
```

### Change Helm chart values

Edit the HelmRelease in `gitops/infrastructure/<service>/helmrelease.yaml`, commit, and push. Flux reconciles within 60 seconds.

### Add a new application

Create a HelmRelease (or ArgoCD Application) in `gitops/apps/` and reference it from `gitops/apps/kustomization.yaml`. See [gitops/README.md](gitops/README.md) for details.

### Enable Let's Encrypt

In `gitops/infrastructure/cert-manager-config/cluster-issuers.yaml`, uncomment the `letsencrypt-staging` / `letsencrypt-prod` issuers and set your email. Then update the `Certificate` resource to use `letsencrypt-prod` as the issuer.

---

## Getting the NVRAM Seed

Tart uses UEFI to boot VMs. Raw disk images need an NVRAM state file seeded with EFI variables so the bootloader can find the OS.

**Option A — extract from a running Tart VM:**
```bash
# Find any existing Tart VM
ls ~/.tart/vms/

# Copy its NVRAM file
cp ~/.tart/vms/<any-vm>/nvram.bin bootstrap/terraform/nvram-arm64.bin
```

**Option B — boot any Tart image once and copy:**
```bash
tart run ghcr.io/cirruslabs/ubuntu:latest &
sleep 10 && tart stop ubuntu
cp ~/.tart/vms/ubuntu/nvram.bin bootstrap/terraform/nvram-arm64.bin
tart delete ubuntu
```

The file is gitignored since it's a binary blob and machine-specific.

---

## Trusting the Self-Signed CA

The wildcard cert is signed by a self-signed root CA managed by cert-manager. To avoid browser warnings, add the CA to your macOS keychain:

```bash
# Export the root CA certificate
kubectl get secret root-ca-secret -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/talos-root-ca.crt

# Add to macOS System keychain and trust it
sudo security add-trusted-cert -d -r trustRoot \
  -k /System/Library/Keychains/SystemRootCertificates.keychain \
  /tmp/talos-root-ca.crt
```

---

## Troubleshooting

### `tofu apply` fails with "invalid network address /32"

One of the VMs returned an empty IP — its ARP entry was incomplete at discovery time. The fix:

```bash
# Restart the problematic VM (usually talos-cp2)
tart stop talos-cp2 && tart run talos-cp2 --no-graphics &
sleep 15
tofu apply   # re-run — the module is idempotent
```

### Nodes not Ready after bootstrap

```bash
export TALOSCONFIG=_out/talosconfig
talosctl health --talosconfig $TALOSCONFIG
```

Cilium takes ~60s to come up. If nodes stay `NotReady` beyond 3 minutes, check Cilium:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium
kubectl logs -n kube-system -l app.kubernetes.io/name=cilium --tail=20
```

### Flux Kustomization stuck / HelmRelease Failed

```bash
flux get all -A                         # overview
flux describe kustomization infrastructure -n flux-system   # details

# Force re-reconcile a specific resource
flux reconcile helmrelease <name> -n <namespace>

# Break a deadlock — annotate the kustomization
kubectl annotate kustomization infrastructure -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
```

### Gateway not PROGRAMMED

The Cilium operator needs to be running to claim the GatewayClass. If the Gateway stays `Unknown` after a fresh cluster, restart the operator:

```bash
kubectl rollout restart deployment/cilium-operator -n kube-system
# Wait ~30 seconds
kubectl get gateway main-gateway -n networking
```

### Loki CrashLoopBackOff on Talos

Talos enforces `readOnlyRootFilesystem` on containers. Loki needs a writable `/var/loki` path. The Loki HelmRelease in this repo already adds an `emptyDir` volume for this — if you see the crash, ensure you're on the latest `main` branch.

---

## Teardown

```bash
cd bootstrap/terraform
tofu destroy
```

> **Note**: `talos_machine_secrets` has `prevent_destroy = true` to protect cluster PKI from accidental deletion. To do a full destroy including secrets:
> ```bash
> tofu state rm 'module.talos.talos_machine_secrets.this'
> tofu destroy
> ```

---

## Roadmap

- [ ] SOPS/age encryption for Kubernetes secrets in GitOps
- [ ] Persistent storage with [OpenEBS](https://openebs.io) or [Longhorn](https://longhorn.io)
- [ ] Let's Encrypt production certificates (ACME via cert-manager)
- [ ] GitHub Actions: validate Flux manifests on PR (`flux build kustomization`)
- [ ] Own Helm chart registry
- [ ] Multi-cluster support (dev + staging clusters)

---

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

[MIT](LICENSE)
