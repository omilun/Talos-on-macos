<div align="center">

# Running your own Kubernetes clusters on macOS using Talos Linux and Tart

[**Talos Linux**](https://talos.dev) is an immutable, API-driven OS built exclusively for Kubernetes.
No SSH. No shell. No config drift. Just a cluster.
This repo brings that production-grade OS to your Mac — fully automated, fully private.

[![Talos Linux](https://img.shields.io/badge/Talos_Linux-v1.13-FF6B6B?style=for-the-badge&logo=linux&logoColor=white)](https://talos.dev)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Cilium](https://img.shields.io/badge/Cilium-eBPF-F8C517?style=for-the-badge&logo=cilium&logoColor=black)](https://cilium.io)
[![Flux](https://img.shields.io/badge/Flux-GitOps-5468FF?style=for-the-badge&logo=flux&logoColor=white)](https://fluxcd.io)
[![Tart](https://img.shields.io/badge/Tart-Apple_Silicon-000000?style=for-the-badge&logo=apple&logoColor=white)](https://tart.run)

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

Mac Mini and MacBook Pro are powerful enough to run a real multi-node Kubernetes cluster.
[Talos Linux](https://talos.dev) is the right OS for it — immutable, API-only, production-grade.
[Tart](https://tart.run) is a free, open-source VM runtime built for Apple Silicon.

**But nobody had wired them together.** Getting Talos Linux running on macOS in a fully automated,
free-of-charge way was either undocumented, manual, or required paid software like Parallels or VMware Fusion.

This repo fixes that. One command provisions a complete Talos Linux HA cluster on your Mac —
no paid tools, no cloud account, no manual steps. Just your Mac and open-source software.

---

## What you get — out of the box, after one command

> *Not a demo. Not a sandbox. A real cluster you'd be proud to show in a job interview.*

**The cluster**
- 🏗 **6-node Talos Linux HA cluster** — 3 control-plane + 3 workers, etcd quorum, automatic node recovery
- ⚡ **Cilium eBPF** — kube-proxy is gone. Networking runs in the kernel. Gateway API, Hubble, L2 LoadBalancer.
- 🔐 **Immutable nodes** — no SSH, no shell, no package manager. Every change goes through the Talos API.

**Networking & HTTPS**
- 🌐 **Real domain names** — `*.talos-on-macos.com` resolves on your Mac without editing `/etc/hosts`
- 🔒 **Green padlock in your browser** — cert-manager issues a wildcard TLS cert from a private CA, trusted by macOS Keychain automatically
- 🚫 **Zero port-forwards** — open `https://argocd.talos-on-macos.com` like a real URL. That's it.

**GitOps & automation**
- 📦 **Flux + ArgoCD** — every component is in git, declarative, and self-healing. Break something? Git reset and reconcile.
- 🤖 **One command deploy** — Talos image auto-downloaded, VMs created, cluster bootstrapped, DNS configured, CA trusted. You watch, it works.
- �� **Flexible node pools** — want a tainted GPU pool? An infra-only CP? Two lines in `terraform.tfvars`.

**Observability — ready, not configured**
- 📊 Grafana · Prometheus · Alertmanager · Loki — dashboards load on first visit, no setup wizard
- 🔭 Hubble UI — live network flow visualisation across the cluster

**The deal**
- 💸 **100% free** — Tart, Talos, OpenTofu, Cilium, Flux — all open source, no licences, no cloud bills
- 🔒 **Stays on your Mac** — no tunnels, no DuckDNS, no exposure to the internet
- 🍎 **Mac Mini / MacBook** — runs on Apple Silicon, sleeps with your laptop, wakes with your cluster still there

---

## Quick start

**Prerequisites** — install once:
```bash
brew install cirruslabs/cli/tart opentofu siderolabs/tap/talosctl \
             kubectl helm fluxcd/tap/flux
```

**Configure** — one line to change:
```bash
cd bootstrap/terraform
cp terraform.tfvars.example terraform.tfvars
# Open terraform.tfvars and set flux_git_repository_url to your fork
```

**Deploy:**
```bash
tofu init && tofu apply
```

Near the end, Terraform will ask for your **sudo password once** — to write `/etc/resolver/talos-on-macos.com` (so your Mac resolves the cluster domains) and add the cluster CA to your macOS Keychain (so the browser shows a green padlock). That's the only manual interaction.

That's it. ~15 minutes later on Apple Silicon:

```
https://argocd.talos-tart-ha.talos-on-macos.com     🔒 green padlock
https://grafana.talos-tart-ha.talos-on-macos.com    🔒 green padlock
https://prometheus.talos-tart-ha.talos-on-macos.com 🔒 green padlock
```

> Prefer non-interactive? Set `export TF_VAR_macos_sudo_password="yourpassword"` before running `tofu apply`.

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
| 📦 [Deploy apps](docs/deploy-apps.md) | Add apps with ArgoCD, CloudNativePG, HTTPS — with the pulse demo app |
| 🌍 [Multi-cluster](docs/multi-cluster.md) | Running multiple clusters side by side |
| 🔧 [Troubleshooting](docs/troubleshooting.md) | Common issues and fixes |
