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
│  │   │                       Gateway + DNS CoreDNS)    │ │
│  │   ├── argocd             (HelmRelease + HTTPRoute)  │ │
│  │   └── monitoring         (kube-prometheus-stack +   │ │
│  │                           Loki + HTTPRoutes)        │ │
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

## Multi-cluster

Each cluster gets its own Flux entrypoint under `gitops/clusters/<cluster_name>/`. The entrypoint references shared infrastructure under `gitops/infrastructure/`. See [multi-cluster.md](multi-cluster.md).
