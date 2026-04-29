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
└── .github/workflows/build.yaml   ← builds and pushes images to ghcr.io
```

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
Go API + Next.js frontend + CloudNativePG + GitHub Actions CI + ArgoCD deploy.

| URL | Service |
|---|---|
| https://pulse.talos-on-macos.com | Next.js frontend |
| https://api.pulse.talos-on-macos.com | Go API |
