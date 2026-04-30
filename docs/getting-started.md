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

> All `*.talos-tart-ha.talos-on-macos.com` subdomains are covered by the wildcard DNS
> configured by `setup-dns.sh` — no per-hostname `/etc/hosts` entries needed.
> If DNS stops resolving after a VM restart, re-run `bash setup-dns.sh`.

---

## Post-deploy checklist

`tofu apply` handles the cluster, GitOps, DNS, and TLS automatically. The steps below are
**one-time manual steps** required to activate the CI pipeline and observability tools.

### 1 · Verify DNS resolves

```bash
bash setup-dns.sh
```

This configures `/etc/resolver/talos-on-macos.com` (wildcard — covers all subdomains),
updates CoreDNS with the Gateway IP, and trusts the cluster CA in macOS Keychain.
Re-run this if you get DNS failures after a VM restart.

If the resolver approach doesn't work on your machine, fall back to `/etc/hosts`:

```bash
GATEWAY_IP=192.168.64.192   # verify with: kubectl get gateway -n networking main-gateway -o jsonpath='{.status.addresses[0].value}'
sudo tee -a /etc/hosts <<EOF
$GATEWAY_IP  argocd.talos-tart-ha.talos-on-macos.com
$GATEWAY_IP  workflows.talos-tart-ha.talos-on-macos.com
$GATEWAY_IP  grafana.talos-tart-ha.talos-on-macos.com
$GATEWAY_IP  prometheus.talos-tart-ha.talos-on-macos.com
$GATEWAY_IP  alertmanager.talos-tart-ha.talos-on-macos.com
$GATEWAY_IP  loki.talos-tart-ha.talos-on-macos.com
$GATEWAY_IP  registry.talos-tart-ha.talos-on-macos.com
$GATEWAY_IP  events.talos-tart-ha.talos-on-macos.com
$GATEWAY_IP  pulse.talos-tart-ha.talos-on-macos.com
EOF
```

### 2 · Set KUBECONFIG

```bash
export KUBECONFIG=~/Codes/Personal/tart-lab/Talos-on-macos/_out/kubeconfig.yaml
# Add to ~/.zshrc or ~/.bash_profile to make it permanent
```

### 3 · Create CI pipeline secrets

Required for the pulse CI conveyor belt to build images and open PRs:

```bash
# GitHub PAT — needs write access to this repo (push branches + open PRs)
# Required scopes: Contents (read/write) and Pull requests (read/write)
kubectl create secret generic github-token -n argo \
  --from-literal=token=<your-GitHub-PAT>

# HMAC secret — copy this value to GitHub webhook settings (step 4)
WEBHOOK_SECRET=$(openssl rand -hex 32)
kubectl create secret generic github-webhook-secret -n argo \
  --from-literal=secret=$WEBHOOK_SECRET
echo "Webhook secret: $WEBHOOK_SECRET"
```

No registry credentials needed — Zot runs without authentication.

### 4 · Configure GitHub webhook

In `omilun/pulse` repo → **Settings → Webhooks → Add webhook**:

| Field | Value |
|---|---|
| Payload URL | `https://events.talos-tart-ha.talos-on-macos.com/pulse/push` |
| Content type | `application/json` |
| Secret | value from `$WEBHOOK_SECRET` (step 3) |
| Events | **Just the push event** |

### 5 · Verify everything is up

```bash
# All Flux KS should show Ready=True
flux get kustomizations -A

# ArgoCD apps should be Synced + Healthy
kubectl -n argocd get application

# CI pipeline components
kubectl -n argo get eventbus,eventsource,sensor
kubectl -n buildkit get pods
```

### 6 · Open the dashboards

| Service | URL | Credentials |
|---|---|---|
| ArgoCD | https://argocd.talos-tart-ha.talos-on-macos.com | `admin` / see secret |
| Grafana | https://grafana.talos-tart-ha.talos-on-macos.com | `admin` / `change-me` |
| Argo Workflows | https://workflows.talos-tart-ha.talos-on-macos.com | — |
| Zot Registry | https://registry.talos-tart-ha.talos-on-macos.com | no auth |

> **Flux resources:** Use the CLI — `flux get all -A` (no web UI: Capacitor and Weave GitOps
> are both incompatible with the current Flux v2 API versions).

---

## Tear down

```bash
tofu destroy
sudo rm -f /etc/resolver/talos-on-macos.com && sudo dscacheutil -flushcache
```
