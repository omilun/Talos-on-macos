# Terraform / OpenTofu — Talos HA Cluster Bootstrap

Declarative, state-managed provisioning of the full cluster stack.
Terraform handles **Day 0** only. Once Flux is bootstrapped, the **Day 1** platform
(networking, cert-manager, ArgoCD, monitoring) is managed via `gitops/` in this repo.

---

## What Terraform Manages

| Module         | Resources                                                          |
|----------------|--------------------------------------------------------------------|
| `tart-vms`     | 6 Tart VMs (create / destroy), IP discovery via ARP               |
| `talos`        | Machine secrets, configs, bootstrap, kubeconfig, CSR approval      |
| `cilium`       | Cilium Helm install: eBPF, kube-proxy replacement, Gateway API     |
| `gateway-api`  | Gateway API CRDs v1.2+ (standard channel, never pruned)            |
| `flux`         | Flux v2 controllers, GitRepository source, Kustomization           |

## What Flux Manages (gitops/)

After Terraform completes, Flux takes over and installs:

- **networking**: GatewayClass, CiliumLBIPPool, L2Policy, shared Gateway
- **cert-manager**: cert-manager Helm, self-signed root CA, wildcard `*.local` cert
- **argocd**: ArgoCD Helm + HTTPRoute on `argocd.local`
- **monitoring**: kube-prometheus-stack (Prometheus + Grafana + Alertmanager) + Loki + Promtail

---

## Prerequisites

```bash
brew install tart tofu helm kubectl fluxcd/tap/flux
```

Talos ARM64 disk image from [factory.talos.dev](https://factory.talos.dev).

---

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if needed (defaults work for Apple Silicon + Tart)

# Provide GitHub token for Flux (optional — only needed if repo is private)
export TF_VAR_flux_github_token="ghp_..."

tofu init
tofu plan    # review the 27-resource plan
tofu apply
```

After apply, all outputs are printed including hints:

```bash
tofu output kubectl_hint    # export KUBECONFIG=...
tofu output flux_hint       # flux get all -A
tofu output etc_hosts_hint  # get LB IP + hostnames
```

---

## Module Details

### `tart-vms`
- Creates 6 Tart VMs using `null_resource` + shell provisioners (not the Tart provider — it doesn't support raw images + custom NVRAM).
- Each VM gets a unique MAC address; IPs are discovered via `arp -a` after boot.
- `for_each` on all VMs allows independent create/destroy.

### `talos`
- Generates Talos machine secrets (persisted in state with `prevent_destroy = true`).
- Applies machine configs to all nodes with per-node route patches (PRIVATE bridge workaround).
- Bootstraps etcd on CP1, waits for API server, writes kubeconfig + talosconfig to `_out/`.

### `cilium`
- Helm install: `kubeProxyReplacement=true`, KubePrism (`localhost:7445`), `gatewayAPI.enabled=true`.
- Uses shell provisioner (not Helm provider) — provider config is static and can't reference kubeconfig from state.

### `gateway-api`
- Applies the official `standard-install.yaml` CRD bundle.
- Never prunes on destroy (CRDs are shared infrastructure).

### `flux`
- Installs Flux controllers via `flux install`.
- Configures `GitRepository` pointing at `https://github.com/omilun/talos-on-macos`.
- Creates `Kustomization` at path `gitops/clusters/tart-lab/`.

---

## Key Variables

| Variable                  | Default                                          | Description                          |
|---------------------------|--------------------------------------------------|--------------------------------------|
| `talos_version`           | `v1.13.0`                                        | Talos Linux version                  |
| `kubernetes_version`      | `1.35.2`                                         | Kubernetes version                   |
| `talos_vip`               | `192.168.64.100`                                 | VIP for macOS → cluster access       |
| `gateway_api_version`     | `v1.2.1`                                         | Gateway API CRDs version             |
| `flux_git_repository_url` | `https://github.com/omilun/talos-on-macos` | Flux GitOps source               |
| `flux_github_token`       | `""` (sensitive)                                 | GitHub PAT for private repos         |

See `terraform.tfvars.example` for all variables.

---

## Teardown

```bash
tofu destroy
```

> **Note**: `talos_machine_secrets` has `prevent_destroy = true`.
> Remove first if you need a full teardown:
> ```bash
> tofu state rm 'module.talos.talos_machine_secrets.this'
> tofu destroy
> ```
