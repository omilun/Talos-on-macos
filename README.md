# Talos on macOS

> Production-like Talos Linux HA Kubernetes cluster on macOS Apple Silicon, automated end-to-end with Terraform and managed day-2 with Flux GitOps.

![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35-326CE5?logo=kubernetes&logoColor=white)
![Talos](https://img.shields.io/badge/Talos-v1.13-FF6B6B?logo=linux&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?logo=terraform&logoColor=white)
![Cilium](https://img.shields.io/badge/Cilium-eBPF-F8C517?logo=cilium&logoColor=black)
![Flux](https://img.shields.io/badge/Flux-GitOps-5468FF?logo=flux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-000000?logo=apple&logoColor=white)

## Overview

This project provisions a 6-node Talos Kubernetes cluster (3 control-plane + 3 workers) entirely on macOS using [Tart](https://tart.run) lightweight VMs. The stack is split into two layers:

| Layer | Tool | Scope |
|---|---|---|
| **Day 0–1** | Terraform / OpenTofu | VMs, Talos, Cilium, Gateway API CRDs, Flux bootstrap |
| **Day 2+** | Flux GitOps | cert-manager, ArgoCD, Prometheus, Grafana, Loki |

## Architecture

```
macOS (Apple Silicon)
└── Tart VMs
    ├── talos-cp1/cp2/cp3  (control-plane, VIP: 192.168.64.100)
    └── talos-w1/w2/w3     (workers)

Kubernetes Platform
├── Cilium          — CNI, kube-proxy replacement, Gateway API controller
├── Gateway API     — HTTPRoute ingress via shared Gateway (cilium class)
├── cert-manager    — self-signed TLS (extendable to ACME)
├── ArgoCD          — app delivery  → argocd.local
├── Prometheus      — metrics       → prometheus.local
├── Grafana         — dashboards    → grafana.local
└── Loki + Promtail — log aggregation
```

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| macOS Apple Silicon | Ventura+ | — |
| [Tart](https://tart.run) | latest | `brew install cirruslabs/cli/tart` |
| [OpenTofu](https://opentofu.org) / Terraform | ≥ 1.8 | `brew install opentofu` |
| [talosctl](https://talos.dev) | ≥ 1.13 | `brew install siderolabs/tap/talosctl` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | ≥ 1.28 | `brew install kubectl` |
| [Helm](https://helm.sh) | ≥ 3.14 | `brew install helm` |
| [flux CLI](https://fluxcd.io/flux/installation/) | ≥ 2.4 | `brew install fluxcd/tap/flux` |

## Quick Start

```bash
# 1. Clone this repo
git clone git@github.com:omilun/Talos-on-macos.git
cd Talos-on-macos/bootstrap/terraform

# 2. Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set flux_git_repository_url at minimum

# 3. Init and apply (provisions everything: VMs → Talos → Cilium → Flux)
tofu init
tofu apply

# 4. Export kubeconfig
export KUBECONFIG=~/.kube/talos-tart
kubectl get nodes
```

## Directory Structure

```
.
├── bootstrap/
│   └── terraform/              # Day 0–1: full cluster provisioning
│       ├── main.tf             # Module orchestration
│       ├── variables.tf        # All inputs (see terraform.tfvars.example)
│       ├── outputs.tf          # IPs, URLs, hints
│       └── modules/
│           ├── tart-vms/       # Create/delete Tart VMs
│           ├── talos/          # Generate & apply Talos configs
│           ├── cilium/         # Cilium Helm install (eBPF + Gateway API)
│           ├── gateway-api/    # Install Gateway API CRDs
│           └── flux/           # Bootstrap Flux controllers + GitRepository
├── gitops/                     # Day 2+: Flux-managed platform
│   ├── clusters/tart-lab/      # Flux entrypoint Kustomizations
│   └── infrastructure/
│       ├── sources/            # HelmRepository declarations
│       ├── networking/         # GatewayClass, LBIPPool, Gateway
│       ├── cert-manager/       # TLS issuers + wildcard cert
│       ├── argocd/             # ArgoCD HelmRelease + HTTPRoute
│       └── monitoring/         # Prometheus, Grafana, Loki, Promtail
└── patches/                    # Talos machine config patches
```

## Access

Add to `/etc/hosts` on your Mac:

```
192.168.64.200  argocd.local
192.168.64.200  grafana.local
192.168.64.200  prometheus.local
192.168.64.200  alertmanager.local
```

| Service | URL |
|---|---|
| ArgoCD | https://argocd.local |
| Grafana | https://grafana.local |
| Prometheus | https://prometheus.local |
| Alertmanager | https://alertmanager.local |

## Teardown

```bash
cd bootstrap/terraform
tofu destroy
```

## Future Work

- [ ] SOPS encryption for secrets (Grafana password, tokens)
- [ ] Own Helm charts at `github.com/omilun/helm-charts`
- [ ] Let's Encrypt production certs via ACME
- [ ] Persistent storage (OpenEBS or Longhorn)
- [ ] GitHub Actions CI for GitOps validation

## License

MIT
