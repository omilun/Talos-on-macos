# Getting Started

## Prerequisites

Install with Homebrew:

```bash
brew install cirruslabs/cli/tart \
             opentofu \
             siderolabs/tap/talosctl \
             kubectl \
             helm \
             fluxcd/tap/flux
```

Verify:

```bash
tart --version && tofu --version && talosctl version --client && flux version
```

## Configuration

```bash
cd ~/Codes/Personal/tart-lab/Talos-on-macos/bootstrap/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

| Variable | Required | Description |
|---|---|---|
| `flux_git_repository_url` | ✅ | Your fork URL: `https://github.com/<you>/Talos-on-macos` |
| `flux_github_token` | For private repos | GitHub PAT with `repo` scope |
| `cluster_name` | Optional | Default: `talos-tart-ha` |
| `talos_version` | Optional | Default: `v1.13.0` |
| `image_path` | Optional | Default: `~/Downloads/metal-arm64.raw` (auto-downloaded) |

### Sudo password (optional)

Terraform needs sudo to write `/etc/resolver` and trust the CA. You can:

**Option A** — let it prompt during `tofu apply` (default behaviour)

**Option B** — provide it upfront via `.env` at the repo root:
```bash
cp .env.example .env
# Edit .env: set SUDO_PASSWORD=yourpassword
```

**Option C** — set in `terraform.tfvars`:
```hcl
macos_sudo_password = "yourpassword"
```

> `.env` and `terraform.tfvars` are gitignored — never committed.

## Deploy

```bash
tofu init
tofu apply
```

Terraform will:
1. Download the Talos disk image if not already present
2. Create 6 Tart VMs (3 control-plane + 3 workers)
3. Generate Talos secrets and machine configs
4. Bootstrap Talos + Kubernetes
5. Install Cilium (eBPF, kube-proxy replacement)
6. Install Gateway API CRDs
7. Bootstrap Flux (GitOps — points at this repo)
8. Wait for cert-manager to issue wildcard TLS cert
9. Wait for Cilium Gateway to get a LoadBalancer IP
10. Configure macOS DNS (`/etc/resolver`) and trust the cluster CA

**Total time: ~15 minutes** on Apple Silicon.

## Access your cluster

After `tofu apply` completes:

```bash
export KUBECONFIG=~/Codes/Personal/tart-lab/Talos-on-macos/_out/kubeconfig.yaml

# Check cluster
kubectl get nodes

# Check Flux
flux get all -A
```

Open dashboards (all HTTPS with green padlock):

| Service | URL |
|---|---|
| ArgoCD | https://argocd.talos-tart-ha.talos-on-macos.com |
| Argo Workflows | https://workflows.talos-tart-ha.talos-on-macos.com |
| Grafana | https://grafana.talos-tart-ha.talos-on-macos.com (admin / change-me) |
| Prometheus | https://prometheus.talos-tart-ha.talos-on-macos.com |
| Alertmanager | https://alertmanager.talos-tart-ha.talos-on-macos.com |
| Zot Registry | https://registry.talos-tart-ha.talos-on-macos.com |

## CI pipeline secrets (one-time setup)

After deploy, create two secrets in the `argo` namespace before the pulse CI pipeline can run:

```bash
# GitHub PAT with repo scope — used by create-pr to open PRs in this repo
kubectl create secret generic github-token -n argo \
  --from-literal=token=<your-PAT>

# HMAC secret — must match what you configure as the webhook secret in GitHub
kubectl create secret generic github-webhook-secret -n argo \
  --from-literal=secret=<hex-secret>
```

No registry credentials needed — Zot runs without authentication.

### GitHub webhook setup

In the `omilun/pulse` repo settings → Webhooks → Add webhook:

| Field | Value |
|---|---|
| Payload URL | `https://events.talos-tart-ha.talos-on-macos.com/pulse/push` |
| Content type | `application/json` |
| Secret | the same `<hex-secret>` used above |
| Events | Just the **push** event |

## Tear down

```bash
tofu destroy
sudo rm -f /etc/resolver/talos-on-macos.com && sudo dscacheutil -flushcache
```
