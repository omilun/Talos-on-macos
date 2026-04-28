# GitOps — Flux Managed Platform

This directory contains all manifests managed by [Flux v2](https://fluxcd.io).
Terraform bootstraps Flux once during Day 0; after that, Git is the source of truth.

## Structure

```
gitops/
├── clusters/tart-lab/           ← Flux entrypoints (synced by Flux itself)
│   ├── infrastructure.yaml      ← Kustomization: reconciles infrastructure/
│   └── apps.yaml                ← Kustomization: reconciles apps/ (after infra)
│
└── infrastructure/
    ├── sources/                 ← HelmRepository declarations
    ├── networking/              ← GatewayClass, LBPool, L2Policy, Gateway
    ├── cert-manager/            ← cert-manager, ClusterIssuers, wildcard cert
    ├── argocd/                  ← ArgoCD, HTTPRoute
    └── monitoring/              ← kube-prometheus-stack, Loki, Promtail, HTTPRoutes
```

## Reconciliation Order

```
sources → networking → cert-manager → argocd → monitoring
```

Each layer depends on the previous via Flux `dependsOn` in HelmRelease resources.

## Adding Applications (Day 2)

Add your application manifests to `apps/`. Options:

1. **ArgoCD `Application`** resource pointing at your Helm chart repo
2. **Flux `HelmRelease`** directly in `apps/`

Future own Helm charts: `github.com/omilun/helm-charts`

## Monitoring Flux

```bash
export KUBECONFIG=../_out/kubeconfig.yaml

flux get all -A                          # status of all Flux resources
flux logs --all-namespaces --follow      # reconciliation events
flux reconcile source git flux-system    # force re-sync from Git
```
