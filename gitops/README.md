# GitOps — Flux-Managed Platform

This directory is the **Day 2+** source of truth for everything running in the cluster after Terraform bootstraps Flux.

> Terraform sets up VMs, Talos, Cilium, and Flux. Once Flux is running, **this directory drives all further changes** — no more `helm install`, no `kubectl apply` by hand.

---

## Structure

```
gitops/
├── clusters/
│   └── tart-lab/
│       ├── infrastructure.yaml     ← Flux Kustomization: reconciles infrastructure/
│       └── apps.yaml               ← Flux Kustomization: reconciles apps/ (after infra)
│
├── infrastructure/
│   ├── kustomization.yaml          ← aggregates all infrastructure sub-dirs
│   ├── sources/                    ← HelmRepository objects (Helm registries)
│   ├── networking/                 ← GatewayClass, CiliumLBIPPool, L2 policy, Gateway
│   ├── cert-manager/               ← cert-manager HelmRelease + namespace
│   ├── cert-manager-config/        ← ClusterIssuers + wildcard cert (after CRDs)
│   ├── argocd/                     ← ArgoCD HelmRelease + HTTPRoute
│   ├── otel/                       ← OTel Operator HelmRelease
│   └── monitoring/                 ← kube-prometheus-stack, Loki, Promtail, Tempo, HTTPRoutes
│
└── apps/                           ← your applications live here
    └── kustomization.yaml
```

---

## Reconciliation Flow

```
Flux watches git → applies clusters/tart-lab/
                         │
                         ├─ Kustomization: infrastructure  (wait: true, timeout: 15m)
                         │    └─ applies infrastructure/
                         │         ├─ sources           HelmRepository objects
                         │         ├─ networking         GatewayClass, LBPool, Gateway
                         │         ├─ cert-manager       Helm install
                         │         ├─ argocd             Helm install
                         │         └─ monitoring         Helm install
                         │
                         ├─ Kustomization: infrastructure-config  (dependsOn: infrastructure)
                         │    └─ applies infrastructure/cert-manager-config/
                         │         ├─ ClusterIssuers     (needs cert-manager CRDs ✓)
                         │         └─ wildcard-local     Certificate resource
                         │
                         ├─ Kustomization: otel-collector  (dependsOn: infrastructure)
                         │    └─ applies infrastructure/otel-collector/
                         │         └─ OpenTelemetryCollector CR (needs OTel Operator CRDs ✓)
                         │
                         └─ Kustomization: apps  (dependsOn: infrastructure)
                              └─ applies apps/
```

### Why two infrastructure Kustomizations?

`ClusterIssuer` resources require cert-manager CRDs to be registered before Flux can apply them (Flux does a dry-run). By splitting into `infrastructure` (installs the HelmRelease, `wait: true`) and `infrastructure-config` (applies ClusterIssuers, `dependsOn: infrastructure`), Flux handles this ordering correctly without manual intervention.

---

## Components

### Networking (`infrastructure/networking/`)

| Resource | Kind | Description |
|----------|------|-------------|
| `cilium` | `GatewayClass` | Registers Cilium as the Gateway API controller |
| `default-pool` | `CiliumLoadBalancerIPPool` | IP range `192.168.64.200/28` for LoadBalancer services |
| `default-l2-policy` | `CiliumL2AnnouncementPolicy` | ARP announcements on the primary NIC (`enp0s1`) |
| `main-gateway` | `Gateway` | Shared ingress point for all services |

### cert-manager (`infrastructure/cert-manager/` + `cert-manager-config/`)

| Resource | Kind | Description |
|----------|------|-------------|
| `cert-manager` | `HelmRelease` | cert-manager v1.20+ with CRD install |
| `selfsigned-issuer` | `ClusterIssuer` | Bootstrap issuer |
| `ca-issuer` | `ClusterIssuer` | Signs all service certs from root CA |
| `letsencrypt-staging` | `ClusterIssuer` | ACME staging (ready to use, just add email) |
| `root-ca` | `Certificate` | Self-signed root CA in `cert-manager` namespace |
| `wildcard-local` | `Certificate` | `*.local` wildcard cert used by all HTTPRoutes |

### ArgoCD (`infrastructure/argocd/`)

| Resource | Kind | Description |
|----------|------|-------------|
| `argocd` | `HelmRelease` | argo-cd v7.9+ |
| `argocd` | `HTTPRoute` | Routes `argocd.local` → ArgoCD server |

### Monitoring (`infrastructure/monitoring/`)

| Resource | Kind | Description |
|----------|------|-------------|
| `kube-prometheus-stack` | `HelmRelease` | Prometheus + Grafana + Alertmanager + node-exporter |
| `loki` | `HelmRelease` | Loki v3 single-binary (emptyDir, dev mode) |
| `promtail` | `HelmRelease` | Log shipper on every node → Loki |
| `tempo` | `HelmRelease` | Grafana Tempo distributed tracing backend (48h retention) |
| `grafana` / `prometheus` / `alertmanager` | `HTTPRoute` | Expose via Gateway |

> **Talos note**: Loki uses `extraVolumes` to mount an `emptyDir` at `/var/loki` because Talos enforces `readOnlyRootFilesystem` on all containers. The monitoring namespace has `pod-security.kubernetes.io/enforce: privileged` to allow node-exporter's host access.

### OTel (`infrastructure/otel/` + `otel-collector/`)

| Resource | Kind | Description |
|----------|------|-------------|
| `opentelemetry-operator` | `HelmRelease` | OTel Operator — manages Collector CRs |
| `otel-collector` | `OpenTelemetryCollector` | Collector pipeline: OTLP in → Tempo + Prometheus + Loki out |

> The `otel-collector` Kustomization has `dependsOn: infrastructure` so the Collector CR is applied
> only after the OTel Operator CRDs are registered (same pattern as `infrastructure-config` for cert-manager).

---

## Making Changes

### Update a Helm chart value

Edit the `HelmRelease` in the relevant directory, commit, and push:

```bash
vim gitops/infrastructure/monitoring/kube-prometheus-stack.yaml
git add -A && git commit -m "feat(monitoring): increase prometheus retention to 60d"
git push
```

Flux reconciles within 60 seconds (default interval). Watch it:

```bash
flux get helmrelease kube-prometheus-stack -n monitoring --watch
```

### Add a new application via ArgoCD

Create an ArgoCD `Application` in `gitops/apps/` and reference it in `gitops/apps/kustomization.yaml`:

```yaml
# gitops/apps/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.example.com
    chart: my-chart
    targetRevision: 1.0.0
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Add a new application via Flux HelmRelease

Add a `HelmRelease` directly in `gitops/apps/`:

```bash
mkdir -p gitops/apps/my-app
# Create namespace.yaml, helmrelease.yaml, kustomization.yaml
```

---

## Monitoring Flux

```bash
# Status overview
flux get all -A

# Watch reconciliation events in real time
flux logs --all-namespaces --follow

# Force re-sync from Git (e.g. after a push)
flux reconcile source git flux-system

# Force reconcile a specific HelmRelease
flux reconcile helmrelease <name> -n <namespace>

# Describe a failed kustomization
flux describe kustomization infrastructure -n flux-system
```

---

## Helm Chart Versions Pinned

HelmReleases use semver ranges rather than exact pinning, to allow patch-level auto-updates within a major version:

| Chart | Range |
|-------|-------|
| argo-cd | `>=7.0.0 <8.0.0` |
| cert-manager | `>=1.17.0 <2.0.0` |
| kube-prometheus-stack | `>=65.0.0 <100.0.0` |
| loki | `>=6.0.0 <7.0.0` |
| promtail | `>=6.0.0 <7.0.0` |
| tempo | `>=1.0.0 <2.0.0` |
| opentelemetry-operator | `>=0.100.0 <1.0.0` |

To lock to exact versions, replace the range with the specific version string.

