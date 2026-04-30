# GitOps

This cluster uses a two-controller GitOps model:
**Flux** manages the platform, **ArgoCD** manages your apps.
They're not redundant — they have different jobs and different owners.

---

## The 3-layer structure

```
gitops/
├── clusters/tart-lab/       ← layer 1: per-cluster Flux bootstrap entrypoint
│   ├── flux-system/         ← Flux's own config (managed by flux bootstrap)
│   ├── apps.yaml            ← Flux KS → gitops/apps/
│   └── infrastructure.yaml  ← Flux KS → gitops/infrastructure/
│
├── infrastructure/          ← layer 2: platform tools (Flux-managed, admin only)
│   ├── sources/             ← HelmRepositories, GitRepositories
│   ├── networking/          ← Cilium Gateway, CoreDNS
│   ├── cert-manager/        ← cert-manager Helm release
│   ├── cert-manager-config/ ← ClusterIssuer + wildcard cert (depends on cert-manager)
│   ├── cloudnativepg/       ← PostgreSQL operator
│   ├── harbor/              ← Zot OCI registry (folder name is legacy)
│   ├── argo-workflows/      ← Argo Workflows
│   ├── argo-events/         ← Argo Events operator
│   ├── argocd/              ← ArgoCD
│   ├── monitoring/          ← kube-prometheus-stack + Loki + Promtail
│   ├── buildkit/            ← buildkitd daemon for cluster-native CI
│   ├── weave-gitops/        ← Flux UI dashboard (Weave GitOps)
│   └── kubelet-csr-approver/
│
└── apps/                    ← layer 3: user workloads (ArgoCD Application objects)
    ├── project.yaml         ← ArgoCD AppProject (boundary/permissions)
    └── pulse/
        ├── argocd-app.yaml  ← ArgoCD Application → omilun/pulse deploy/
        ├── namespace.yaml
        └── ci/
            ├── argocd-app.yaml   ← ArgoCD Application → gitops/apps/pulse/ci/
            ├── eventbus.yaml
            ├── eventsource.yaml
            ├── sensor.yaml
            ├── workflow-template.yaml
            └── rbac.yaml
```

---

## Flux = admin layer

Flux has cluster-admin and manages everything in `infrastructure/` and `apps/`.

**What Flux does:**
- Installs and upgrades all platform tools (HelmReleases)
- Creates ArgoCD `Application` objects (the bridge to layer 3)
- Enforces dependency order (`dependsOn`) so cert-manager is ready before ArgoCD, etc.
- Self-heals — if someone manually deletes a HelmRelease, Flux recreates it

**What Flux does NOT do:**
- Deploy your app workloads directly (that's ArgoCD's job)
- Watch your app repos

### Flux reconciliation cycle

Flux polls the git repo every **10 minutes** by default. To force an immediate reconcile:

```bash
# Force all Kustomizations to reconcile
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization infrastructure --with-source
flux reconcile kustomization apps --with-source

# Or annotate directly (works for any KS)
kubectl -n flux-system annotate kustomization apps \
  reconcile.fluxcd.io/requestedAt="$(date -u +%FT%TZ)" --overwrite
```

### Checking Flux status

```bash
# All Kustomizations and HelmReleases
flux get all -A

# Flux controller logs
flux logs --all-namespaces --level=error

# Specific KS detail
kubectl -n flux-system describe kustomization infrastructure
```

---

## ArgoCD = user layer

ArgoCD watches app repos and syncs workload manifests to the cluster.

**What ArgoCD does:**
- Watches `omilun/pulse` for changes to `deploy/`
- Diffs current cluster state vs git, syncs on divergence
- Shows sync status, health, and pod state in the UI
- Prunes resources removed from git (with `automated.prune: true`)

**What ArgoCD does NOT do:**
- Install platform tools (that's Flux)
- Bootstrap itself — Flux installs ArgoCD and creates its `Application` objects

### Admin / user separation in practice

```
Flux applies gitops/apps/pulse/argocd-app.yaml
  → creates ArgoCD Application object in cluster

ArgoCD reads that Application
  → watches omilun/pulse repo
  → syncs deploy/ manifests into pulse namespace
```

Neither controller steps on the other. If you delete the ArgoCD Application by hand,
Flux recreates it on the next reconcile. If a pod crashes, ArgoCD's self-heal restarts it.

---

## Adding a new infrastructure module

1. Create a directory under `gitops/infrastructure/my-tool/`:

```bash
mkdir gitops/infrastructure/my-tool
```

2. Add a `kustomization.yaml` and your manifests (e.g. a HelmRelease):

```yaml
# gitops/infrastructure/my-tool/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helmrelease.yaml
```

3. Register it in `gitops/infrastructure/kustomization.yaml`:

```yaml
resources:
  - sources
  - networking
  - cert-manager
  - my-tool    # add here, order matters for dependsOn
  - argocd
  ...
```

4. Push and reconcile:

```bash
git add gitops/infrastructure/my-tool/
git commit -m "feat(infra): add my-tool"
git push
flux reconcile kustomization infrastructure --with-source
```

---

## Adding a new app

See [deploy-apps.md](deploy-apps.md) for the full walkthrough.
The short version: add an `argocd-app.yaml` under `gitops/apps/my-app/`
and register it in `gitops/apps/kustomization.yaml`.

---

## Dependency ordering

Flux uses `dependsOn` to sequence the infrastructure layers:

```
cert-manager
  └── cert-manager-config  (needs cert-manager CRDs to exist first)

networking
  └── (everything else needs the Gateway to exist)

infrastructure  (all modules reconcile in parallel within this KS)
  └── infrastructure-config  (cert issuers + certs — depends on infrastructure)
    └── apps  (ArgoCD Applications — depends on ArgoCD being up)
```

The `apps` KS has `dependsOn: infrastructure` so ArgoCD always exists before
Flux tries to create Application objects.

---

## Debugging Flux

```bash
# Is a KS stuck?
kubectl -n flux-system get kustomization
kubectl -n flux-system describe kustomization <name>

# Is a HelmRelease failing?
kubectl -n <namespace> get helmrelease
kubectl -n <namespace> describe helmrelease <name>

# Watch Flux events
kubectl -n flux-system get events --sort-by='.lastTimestamp' | tail -20

# Check which revision is applied vs attempted
kubectl -n flux-system get kustomization infrastructure \
  -o jsonpath='{.status.lastAppliedRevision} vs {.status.lastAttemptedRevision}'
```

Common causes of a stuck KS:
- A Deployment in the KS is not becoming `Ready` (health check timeout = 15m)
- A missing Secret that a volume mount depends on
- CRDs not yet installed when a CR referencing them is applied (fix with `dependsOn`)

---

## Flux UI — Weave GitOps

The cluster ships with [Weave GitOps](https://docs.gitops.weave.works/) — a browser dashboard
for Flux maintained by the Flux team.

**URL:** https://flux.talos-tart-ha.talos-on-macos.com  
**Login:** `admin` / `flux-admin`

What you can see:
- All Flux Kustomizations and their sync status / last applied revision
- HelmReleases and chart versions
- GitRepository / HelmRepository / OCIRepository sources
- Runtime — Flux controller pods and versions
- Violations tab (policy, if applicable)

> **Note:** Weave GitOps v0.38.0 uses `v1` Flux APIs (GitRepository, Kustomization, HelmRelease).
> Older Capacitor v0.4.x only supports the deprecated `v1beta2` APIs and will show an empty
> dashboard on this cluster — that's why we use Weave GitOps instead.
