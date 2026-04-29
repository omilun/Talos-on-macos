# Talos on macOS

> One command. Six nodes. Kubernetes on your MacBook.

[![Talos](https://img.shields.io/badge/Talos-v1.13-FF6B6B?logo=linux&logoColor=white)](https://talos.dev)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Cilium](https://img.shields.io/badge/Cilium-eBPF-F8C517?logo=cilium&logoColor=black)](https://cilium.io)
[![Flux](https://img.shields.io/badge/Flux-GitOps-5468FF?logo=flux&logoColor=white)](https://fluxcd.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A fully-automated, production-grade Talos Linux HA Kubernetes cluster running privately on macOS Apple Silicon — provisioned in a single `tofu apply`.

## What you get

| | |
|---|---|
| 🖥 **6-node HA cluster** | 3 control-plane + 3 workers via [Tart](https://tart.run) VMs |
| 🔒 **Cilium eBPF** | kube-proxy replacement, Gateway API, Hubble observability |
| 🌐 **Gateway API** | Trusted HTTPS on real domain names — no `/etc/hosts`, no ports |
| 📦 **GitOps** | Flux + ArgoCD — every component is declarative and self-healing |
| 📊 **Observability** | Grafana, Prometheus, Alertmanager, Loki — ready out of the box |
| 🔑 **Private CA** | cert-manager issues a wildcard cert trusted by your Mac |
| 🤖 **Fully automated** | Talos image auto-downloaded, DNS configured, CA trusted — zero manual steps |

## Quick start

```bash
# 1. Install prerequisites (one-time)
brew install cirruslabs/cli/tart opentofu siderolabs/tap/talosctl \
             kubectl helm fluxcd/tap/flux

# 2. Configure
cd ~/Codes/Personal/tart-lab/Talos-on-macos/bootstrap/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set your GitHub token and repo URL

# 3. Deploy
tofu init && tofu apply
```

That's it. Terraform provisions VMs, bootstraps Talos and Kubernetes, installs Cilium, bootstraps Flux, configures DNS, and trusts the CA — all in one run.

When complete, open your dashboards:

```
https://argocd.talos-tart-ha.talos-on-macos.com     🔒
https://grafana.talos-tart-ha.talos-on-macos.com    🔒
https://prometheus.talos-tart-ha.talos-on-macos.com 🔒
```

## Tear down

```bash
tofu destroy
sudo rm -f /etc/resolver/talos-on-macos.com && sudo dscacheutil -flushcache
```

## Learn more

- [Getting started](docs/getting-started.md) — prerequisites, configuration, first deploy
- [Architecture](docs/architecture.md) — how the pieces fit together
- [Node pools](docs/node-pools.md) — CP as worker, tainted pools, infra nodes, recipes
- [Multi-cluster](docs/multi-cluster.md) — running multiple named clusters side by side
- [Troubleshooting](docs/troubleshooting.md) — common issues and fixes
