# Architecture

## Stack overview

```
┌──────────────────────────────────────────────────────────┐
│  macOS Host (Apple Silicon)                              │
│                                                          │
│  ┌───────────────── Terraform (OpenTofu) ─────────────┐ │
│  │  1. Tart VMs: 3× control-plane + 3× worker         │ │
│  │  2. Talos bootstrap → Kubernetes                    │ │
│  │  3. Cilium CNI install (Helm, kube-proxy off)       │ │
│  │  4. Gateway API CRDs                                │ │
│  │  5. Flux bootstrap (points at this repo)            │ │
│  │  6. macOS host: /etc/resolver + CA Keychain trust   │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────── Flux (GitOps) ───────────────────┐ │
│  │  gitops/infrastructure/                             │ │
│  │   ├── cert-manager      (HelmRelease)               │ │
│  │   ├── cert-manager-config (ClusterIssuer + Cert)    │ │
│  │   ├── networking         (Cilium GatewayClass +     │ │
│  │   │                       Gateway + CoreDNS)        │ │
│  │   ├── kubelet-csr-approver                          │ │
│  │   ├── cloudnativepg      (PostgreSQL operator)      │ │
│  │   ├── harbor/            (deploys Zot OCI Registry) │ │
│  │   ├── argo-workflows     (HelmRelease + HTTPRoute)  │ │
│  │   ├── argo-events        (operator)                 │ │
│  │   ├── argocd             (HelmRelease + HTTPRoute)  │ │
│  │   ├── buildkit           (buildkitd daemon)         │ │
│  │   └── monitoring         (kube-prometheus-stack +   │ │
│  │                           Loki + Promtail)          │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌─────────────── ArgoCD (app workloads) ─────────────┐ │
│  │  gitops/apps/  (Applications created by Flux)       │ │
│  │   ├── pulse        (Go API + Next.js + CNPG)        │ │
│  │   └── pulse-ci     (EventSource + Sensor + WfT)     │ │
│  └─────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

## Networking

All VMs share the `bridge100` interface (192.168.64.0/24) created by macOS Internet Sharing.

```
macOS host
  └── bridge100 (192.168.64.1)
        ├── cp-0   192.168.64.x (DHCP, static MAC)
        ├── cp-1   192.168.64.x
        ├── cp-2   192.168.64.x
        ├── worker-0 ...
        ├── worker-1 ...
        └── worker-2 ...

Cluster VIP (Talos): 192.168.64.50 (etcd/API endpoint)
Gateway LoadBalancer IP: 192.168.64.200-214 (CiliumLoadBalancerIPPool)
```

Inter-VM routing uses static `/32` routes injected by Talos machine config patches (VMs on the same bridge can't talk directly — macOS NAT quirk).

## GitOps repo structure

Standard Flux 3-layer pattern:

```
gitops/
├── clusters/tart-lab/          ← Flux bootstrap entrypoint per cluster
│   ├── apps.yaml               ← KustomizationSync → gitops/apps
│   └── infrastructure.yaml     ← KustomizationSync → gitops/infrastructure
├── infrastructure/             ← reusable modules (Flux-managed)
│   ├── argo-events/
│   ├── argo-workflows/
│   ├── argocd/
│   ├── buildkit/
│   ├── cert-manager/
│   ├── cert-manager-config/
│   ├── cloudnativepg/
│   ├── harbor/                 (deploys Zot — name is legacy)
│   ├── kubelet-csr-approver/
│   ├── monitoring/
│   ├── networking/
│   └── sources/
└── apps/                       ← user workloads (ArgoCD-managed)
    ├── project.yaml            ← ArgoCD AppProject
    └── pulse/
        ├── argocd-app.yaml
        ├── deploy/             ← lives in omilun/pulse repo
        └── ci/
            ├── argocd-app.yaml
            ├── eventbus.yaml
            ├── eventsource.yaml
            ├── sensor.yaml
            ├── workflow-template.yaml
            ├── httproute.yaml
            └── rbac.yaml
```

Flux owns the `clusters/` and `infrastructure/` layers.
ArgoCD owns the `apps/` layer — Application objects are created by Flux, then ArgoCD takes over reconciliation of each app from its own source repo.

## DNS

- Custom CoreDNS (NodePort 30053 on CP node) serves `talos-on-macos.com`
- macOS `/etc/resolver/talos-on-macos.com` → `192.168.64.x:30053`
- All `*.talos-on-macos.com` subdomains resolve to the Gateway's LoadBalancer IP
- Written by `setup-dns.sh` during `tofu apply`

## TLS / HTTPS

```
cert-manager (private CA)
  └── ClusterIssuer: ca-issuer
        └── Certificate: wildcard-cluster-tls
              └── Secret: wildcard-cluster-tls (ns: networking)
                    └── Cilium Gateway (HTTPS :443)
                          └── HTTPRoutes → Services
```

- `cert-manager-config` deploys after `infrastructure` (Flux `dependsOn`)
- The wildcard cert covers `*.talos-tart-ha.talos-on-macos.com`
- `trust-ca.sh` exports the CA and adds it to macOS System Keychain → browser shows 🔒

## Zot OCI Registry

Deployed by the `harbor/` infrastructure module (name is legacy — it deploys [Zot](https://zotregistry.dev), not Harbor).

- **No authentication** — intentional for a local-only cluster
- **arm64-native** CNCF project, OCI distribution spec compliant
- Runs in the `registry` namespace
- Accessible at `https://registry.talos-tart-ha.talos-on-macos.com` (Zot UI + API)

Push and pull images from anywhere on your Mac:
```bash
docker push registry.talos-tart-ha.talos-on-macos.com/my-app:latest
docker pull registry.talos-tart-ha.talos-on-macos.com/my-app:latest
```

The cluster-native CI pipeline (`buildkit`) pushes `sha-<7char>` tagged images here automatically.

## CI/CD Conveyor Belt

Cluster-native CI — no GitHub Actions runners, no cloud build services.

```
Developer push → GitHub webhook
  └── Argo Events EventSource  (validates HMAC, ns: argo)
        └── EventBus (NATS)
              └── Sensor  →  triggers pulse-build WorkflowTemplate
                    └── Argo Workflows DAG
                          ├── build auth-service      (BuildKit)
                          ├── build task-service      (BuildKit)
                          ├── build notification-svc  (BuildKit)
                          └── build frontend          (BuildKit)
                                └── push images: registry.../sha-<7char>
                                      └── create-pr step
                                            └── opens PR in Talos-on-macos repo
                                                  └── merge → ArgoCD auto-sync
                                                        └── pods roll out
```

**Key components:**

| Component | Role |
|---|---|
| Argo Events EventSource | Receives GitHub webhook at `https://events.talos-tart-ha.talos-on-macos.com/pulse/push` |
| EventBus | NATS message broker between EventSource and Sensor |
| Sensor | Subscribes to EventBus, fires WorkflowTemplate with commit SHA |
| WorkflowTemplate `pulse-build` | Defines the 4-parallel-build DAG + `create-pr` step |
| BuildKit daemon | `buildkitd` running in `buildkit` namespace; Workflow steps connect to it |
| Zot Registry | Receives pushed images, tagged `sha-<7char>` |
| `create-pr` | Clones this repo, patches image tags in `apps/pulse/deploy/`, opens a PR |
| ArgoCD | Detects merged PR, syncs pods with new SHA-tagged images |

## Multi-cluster

Each cluster gets its own Flux entrypoint under `gitops/clusters/<cluster_name>/`. The entrypoint references shared infrastructure under `gitops/infrastructure/`. See [multi-cluster.md](multi-cluster.md).
