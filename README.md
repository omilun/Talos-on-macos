<div align="center">

### Run the Kubernetes OS on your MacBook — like it was meant to be there.

# Talos Linux · Local HA Lab on Apple Silicon

[**Talos Linux**](https://talos.dev) is an immutable, API-driven OS built exclusively for Kubernetes.
No SSH. No shell. No config drift. Just a cluster.
This repo brings that production-grade OS to your Mac — fully automated, fully private.

[![Talos](https://img.shields.io/badge/Talos_Linux-v1.13-FF6B6B?style=for-the-badge&logo=linux&logoColor=white)](https://talos.dev)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Cilium](https://img.shields.io/badge/Cilium-eBPF-F8C517?style=for-the-badge&logo=cilium&logoColor=black)](https://cilium.io)
[![Flux](https://img.shields.io/badge/Flux-GitOps-5468FF?style=for-the-badge&logo=flux&logoColor=white)](https://fluxcd.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-22c55e?style=for-the-badge)](LICENSE)

</div>

---

## Why Talos Linux?

Most local Kubernetes setups (kind, minikube, k3s) run on a general-purpose Linux OS
with SSH, a package manager, and a shell — fine for demos, wrong for learning production ops.

[**Talos Linux**](https://talos.dev) is different:

- **Immutable OS** — the filesystem is read-only. Every change goes through the API.
- **No SSH, no shell** — the entire node is managed via `talosctl`. That's it.
- **API-first** — machine configs are YAML documents applied over mTLS. Fully declarative.
- **Minimal attack surface** — Talos ships only what Kubernetes needs. Nothing else.
- **Used in production** — the same OS you'd deploy on bare metal or cloud VMs.

Running Talos locally means you practice the real thing — not a simplified stand-in.

---

## The problem this solves

## The problem this solves

You want to learn, test, and build on the same stack you'd run in production —
Talos Linux, Cilium, Gateway API, Flux, ArgoCD — but spinning up a cloud cluster
for every experiment is slow, expensive, and you lose it when you close the laptop.

**This repo is the answer.** One `tofu apply` and your MacBook runs a 6-node Talos Linux HA cluster
that outlives your terminal session — with real HTTPS, GitOps, and full observability.

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
