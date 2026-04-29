<div align="center">

# 🖥️ Talos on macOS

### A production-grade Kubernetes cluster on your MacBook — in one command.

Not kind. Not minikube. A **real** 6-node HA cluster running Talos Linux,
Cilium eBPF, GitOps, and HTTPS dashboards — entirely local, entirely private.

[![Talos](https://img.shields.io/badge/Talos-v1.13-FF6B6B?style=for-the-badge&logo=linux&logoColor=white)](https://talos.dev)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Cilium](https://img.shields.io/badge/Cilium-eBPF-F8C517?style=for-the-badge&logo=cilium&logoColor=black)](https://cilium.io)
[![Flux](https://img.shields.io/badge/Flux-GitOps-5468FF?style=for-the-badge&logo=flux&logoColor=white)](https://fluxcd.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-22c55e?style=for-the-badge)](LICENSE)

</div>

---

## The problem

You want to learn, test, and build on the same stack you'd run in production —
Talos Linux, Cilium, Gateway API, Flux, ArgoCD — but spinning up a cloud cluster
for every experiment is slow, expensive, and you lose it when you close the laptop.

**This repo is the answer.** One `tofu apply` and your MacBook becomes a Kubernetes lab
that outlives your terminal session.

---

## What you get

| | |
|---|---|
| 🏗 **HA cluster** | 3 control-plane + 3 worker nodes via [Tart](https://tart.run) VMs on Apple Silicon |
| ⚡ **Cilium eBPF** | kube-proxy fully replaced — Gateway API, Hubble, L2 LB announcements |
| 🌐 **Real HTTPS** | `*.talos-on-macos.com` resolves on your Mac, certs trusted by your browser — no `--insecure`, no port-forwards |
| �� **Fully automated** | Disk image auto-downloaded, DNS configured, CA installed to Keychain — zero manual steps |
| 📦 **GitOps** | Flux + ArgoCD — every component is declarative, self-healing, and in git |
| 📊 **Observability** | Grafana · Prometheus · Alertmanager · Loki — wired up and reachable at deploy time |
| 🧩 **Flexible nodes** | Declare any number of node pools with custom CPU/RAM/labels/taints in `terraform.tfvars` |
| 🔒 **Stays private** | Nothing exposed outside your laptop — no tunnels, no cloud DNS, no DuckDNS |

---

## Quick start

**Prerequisites** — install once:
```bash
brew install cirruslabs/cli/tart opentofu siderolabs/tap/talosctl \
             kubectl helm fluxcd/tap/flux
```

**Configure** — two lines:
```bash
cd bootstrap/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — change flux_git_repository_url to your fork
```

**Deploy:**
```bash
tofu init && tofu apply
```

That's it. ~15 minutes later on Apple Silicon:

```
https://argocd.talos-tart-ha.talos-on-macos.com     🔒 green padlock
https://grafana.talos-tart-ha.talos-on-macos.com    🔒 green padlock
https://prometheus.talos-tart-ha.talos-on-macos.com 🔒 green padlock
```

---

## Architecture at a glance

```
┌─ macOS (Apple Silicon) ───────────────────────────────────────────────┐
│                                                                       │
│  tofu apply                                                           │
│   ├── Downloads Talos image (once)                                    │
│   ├── Creates 6 Tart VMs  ──────────────────────────────────────┐    │
│   │   cp-1  cp-2  cp-3  (etcd + API server)                     │    │
│   │   worker-1  worker-2  worker-3                               │    │
│   ├── Bootstraps Talos → Kubernetes                              │    │
│   ├── Installs Cilium (eBPF, kube-proxy off)                     │    │
│   ├── Bootstraps Flux ──────────────────────────────────────┐    │    │
│   │   cert-manager  →  private CA  →  wildcard TLS cert     │    │    │
│   │   Cilium Gateway  →  HTTPS :443  →  HTTPRoutes          │    │    │
│   │   ArgoCD · Grafana · Prometheus · Loki                  │    │    │
│   └── Configures macOS: /etc/resolver + Keychain CA trust        │    │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Tear down

```bash
tofu destroy
sudo rm -f /etc/resolver/talos-on-macos.com
```

---

## Docs

| | |
|---|---|
| 🚀 [Getting started](docs/getting-started.md) | Prerequisites, config, first deploy |
| 🏛 [Architecture](docs/architecture.md) | Stack layers, networking, DNS/TLS |
| 🧩 [Node pools](docs/node-pools.md) | CP as worker, tainted pools, infra nodes, recipes |
| 🌍 [Multi-cluster](docs/multi-cluster.md) | Running multiple clusters side by side |
| 🔧 [Troubleshooting](docs/troubleshooting.md) | Common issues and fixes |
