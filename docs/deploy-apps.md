# Deploying Applications with ArgoCD

> Flux manages infrastructure. ArgoCD manages your apps. This is the clean separation.

---

## How it works

```
Your app repo (e.g. github.com/omilun/pulse)
  └── deploy/                   ← Kubernetes manifests
        ├── kustomization.yaml
        ├── backend.yaml
        ├── frontend.yaml
        ├── db.yaml             ← CloudNativePG Cluster
        └── httproutes.yaml     ← attach to the shared Cilium Gateway

This infra repo (Talos-on-macos)
  └── gitops/apps/
        └── pulse/
              └── argocd-app.yaml  ← ArgoCD Application (managed by Flux)
```

Flux reconciles `gitops/apps/` and creates the ArgoCD Application object.  
ArgoCD then takes over: watches your app repo, diffs, syncs.

---

## Add a new application

### 1 · Create your app repo

Your app repo needs a `deploy/` directory with a `kustomization.yaml`:

```
my-app/
├── deploy/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── httproute.yaml
```

Images are built by the cluster-native CI pipeline (see [Cluster-native CI](#cluster-native-ci-with-argo-events--buildkit) below) and pushed to the in-cluster Zot registry. Reference them as `registry.talos-tart-ha.talos-on-macos.com/my-app:sha-<7char>` in your manifests.

### 2 · Add an ArgoCD Application in this repo

Create `gitops/apps/<your-app>/argocd-app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: apps
  source:
    repoURL: https://github.com/omilun/my-app
    targetRevision: main
    path: deploy
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Also add a `kustomization.yaml` alongside it:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - argocd-app.yaml
```

### 3 · Register it in `gitops/apps/kustomization.yaml`

```yaml
resources:
  - project.yaml
  - pulse         # existing
  - my-app        # add this
```

### 4 · Commit and push — Flux does the rest

```bash
git add gitops/apps/my-app/
git commit -m "feat: add my-app ArgoCD Application"
git push
```

Flux picks up the change in ≤10 minutes, creates the ArgoCD Application,
and ArgoCD syncs your app from its repo.

---

## HTTPS for your app

Add an HTTPRoute in your app repo's `deploy/` directory. It attaches to the
shared Cilium Gateway that's already running:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-app
spec:
  parentRefs:
    - name: main-gateway
      namespace: networking
  hostnames:
    - "my-app.talos-on-macos.com"
  rules:
    - backendRefs:
        - name: my-app
          port: 8080
```

The domain resolves automatically (CoreDNS wildcard) and the TLS cert is already
issued (wildcard cert from cert-manager). Your app gets HTTPS with a green padlock
with zero extra config.

---

## Using CloudNativePG

Add a `Cluster` resource in your app's `deploy/` directory:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-app-db
  namespace: my-app
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:16
  storage:
    size: 2Gi
  bootstrap:
    initdb:
      database: myapp
      owner: myapp
      secret:
        name: my-app-db-credentials
```

The CloudNativePG operator (installed by Flux) automatically:
- Creates the PostgreSQL pod
- Creates a `my-app-db-app` Secret with a `uri` key — use it in your Deployment:

```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: my-app-db-app
        key: uri
```

---

## Argo Workflows

Argo Workflows is installed and accessible at:
```
https://workflows.talos-tart-ha.talos-on-macos.com
```

Submit a workflow from kubectl:
```bash
kubectl create -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: hello-
  namespace: argo
spec:
  entrypoint: say-hello
  templates:
    - name: say-hello
      container:
        image: alpine
        command: [echo]
        args: ["Hello from Argo Workflows!"]
EOF
```

---

## Demo app: pulse

The [pulse](https://github.com/omilun/pulse) app is a working example of this entire pattern:
Go API + Next.js frontend + CloudNativePG + cluster-native CI + ArgoCD deploy.

| URL | Service |
|---|---|
| https://pulse.talos-tart-ha.talos-on-macos.com | Next.js frontend |
| https://api.pulse.talos-tart-ha.talos-on-macos.com | Go API |

CI is handled by the in-cluster conveyor belt — a push to `omilun/pulse` triggers Argo Events,
which runs a BuildKit DAG in Argo Workflows, pushes images to Zot, then opens a PR here to
update image tags. Merge the PR and ArgoCD rolls out the new pods.

---

## Cluster-native CI with Argo Events + BuildKit

The cluster runs a full CI conveyor belt. No GitHub Actions runners required.

### How a build flows

1. Developer pushes to `omilun/pulse` main branch
2. GitHub sends webhook → `https://events.talos-tart-ha.talos-on-macos.com/pulse/push`
3. Argo Events EventSource validates the HMAC secret and publishes to EventBus (NATS)
4. Sensor picks up the event, triggers the `pulse-build` WorkflowTemplate with the commit SHA
5. Argo Workflows runs a DAG: 4 parallel BuildKit builds (auth-service, task-service, notification-service, frontend)
6. Images tagged `sha-<7char>` are pushed to `registry.talos-tart-ha.talos-on-macos.com`
7. A `create-pr` step clones this repo, patches image tags in `apps/pulse/deploy/`, and opens a PR
8. Merge the PR → ArgoCD auto-syncs → pods roll out with the new SHA-tagged images

### Required secrets (one-time setup)

```bash
# GitHub PAT with repo scope (for opening PRs)
kubectl create secret generic github-token -n argo \
  --from-literal=token=<PAT>

# HMAC secret — must match the webhook secret configured in GitHub
kubectl create secret generic github-webhook-secret -n argo \
  --from-literal=secret=<hex>

# No registry credentials needed — Zot has no auth
```

### Zot Registry

All images live at `registry.talos-tart-ha.talos-on-macos.com`.

```bash
# Push from your Mac
docker push registry.talos-tart-ha.talos-on-macos.com/my-app:latest

# Pull inside the cluster
image: registry.talos-tart-ha.talos-on-macos.com/my-app:sha-abc1234
```

Browse the registry UI at `https://registry.talos-tart-ha.talos-on-macos.com`.

### CI resources in git

The CI pipeline lives in `gitops/apps/pulse/ci/` in this repo:

| File | Purpose |
|---|---|
| `eventbus.yaml` | NATS EventBus |
| `eventsource.yaml` | GitHub webhook receiver |
| `sensor.yaml` | Wires EventBus → WorkflowTemplate trigger |
| `workflow-template.yaml` | 4-parallel BuildKit DAG + create-pr step |
| `httproute.yaml` | Exposes the EventSource webhook endpoint |
| `rbac.yaml` | ServiceAccount + roles for workflow steps |
| `argocd-app.yaml` | ArgoCD Application for the CI resources (created by Flux) |
