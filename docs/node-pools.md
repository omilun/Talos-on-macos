# Node Pools — Recipes & Reference

> Full reference for `node_pools` and `allow_scheduling_on_controlplane` in `terraform.tfvars`.

---

## How it works

Each entry in `node_pools` creates `count` VMs that share the same CPU, RAM, Kubernetes labels, and taints.  
Terraform expands the list at plan time — no manual node entries, no hard-coded MACs.

```hcl
node_pools = [
  {
    name      = "<prefix>"        # VM names: <prefix>-1, <prefix>-2, …
    role      = "controlplane"    # or "worker"
    count     = 3                 # number of VMs in this pool
    cpu       = 2                 # vCPUs per VM
    memory_gb = 4                 # RAM per VM in GiB

    # Optional — Kubernetes labels applied to every node in this pool
    labels = { "key" = "value" }

    # Optional — Kubernetes taints applied to every node in this pool
    taints = [
      { key = "key", value = "value", effect = "NoSchedule" }
      # effect: NoSchedule | PreferNoSchedule | NoExecute
    ]
  },
]
```

By default control-plane nodes carry the Kubernetes taint  
`node-role.kubernetes.io/control-plane:NoSchedule`.  
Set `allow_scheduling_on_controlplane = true` to remove it from all CP nodes.

---

## Recipes

### 1 · Default (3 CP + 3 workers, no scheduling on CP)

Standard HA setup. Control-plane nodes do not accept user workloads.

```hcl
node_pools = [
  { name = "cp",     role = "controlplane", count = 3, cpu = 2, memory_gb = 4 },
  { name = "worker", role = "worker",        count = 3, cpu = 2, memory_gb = 4 },
]
# allow_scheduling_on_controlplane = false  (default)
```

**Result:** 6 VMs. CP nodes: `cp-1`, `cp-2`, `cp-3`. Workers: `worker-1`, `worker-2`, `worker-3`.

---

### 2 · CP nodes also run workloads

All CP nodes lose the `node-role.kubernetes.io/control-plane:NoSchedule` taint.  
Normal Pods (without tolerations) can land on them.

```hcl
allow_scheduling_on_controlplane = true

node_pools = [
  { name = "cp",     role = "controlplane", count = 3, cpu = 4, memory_gb = 4 },
  { name = "worker", role = "worker",        count = 3, cpu = 2, memory_gb = 4 },
]
```

**When to use:** homelab with limited RAM — no reason to leave CP CPUs idle.

---

### 3 · Tiny / single-node cluster (1 CP, no workers)

One node does everything.

```hcl
allow_scheduling_on_controlplane = true

node_pools = [
  { name = "cp", role = "controlplane", count = 1, cpu = 4, memory_gb = 8 },
]
```

> ⚠️ Not HA — fine for local development, not for testing Flux failover.

---

### 4 · One dedicated "infra CP" for infrastructure workloads

Three CPs total. Two run only etcd/API-server. One ("infra") also accepts
infrastructure workloads (Prometheus, Loki, cert-manager…).

```hcl
allow_scheduling_on_controlplane = true  # removes CP taint from all CPs

node_pools = [
  # Two regular CPs — no labels/taints; they accept workloads because the
  # CP taint is removed, but you choose not to schedule anything extra there.
  { name = "cp", role = "controlplane", count = 2, cpu = 2, memory_gb = 4 },

  # One "infra CP" — accepts ONLY workloads that tolerate this taint.
  {
    name      = "cp-infra"
    role      = "controlplane"
    count     = 1
    cpu       = 4
    memory_gb = 8
    labels    = { "node-type" = "infra" }
    taints    = [{ key = "node-type", value = "infra", effect = "NoSchedule" }]
  },

  { name = "worker", role = "worker", count = 2, cpu = 2, memory_gb = 4 },
]
```

**Targeting infra workloads to the infra CP** — add to your HelmRelease / Deployment:

```yaml
tolerations:
  - key: node-type
    value: infra
    effect: NoSchedule
nodeSelector:
  node-type: infra
```

---

### 5 · Tainted worker pools (dedicated workload classes)

Different worker pools for different workload types.  
Pods that do not tolerate the taint are **never** scheduled on those nodes.

```hcl
node_pools = [
  { name = "cp",    role = "controlplane", count = 3, cpu = 2, memory_gb = 4 },
  { name = "worker",role = "worker",        count = 2, cpu = 2, memory_gb = 4 },

  # High-memory pool — for Loki / Prometheus
  {
    name      = "fat"
    role      = "worker"
    count     = 1
    cpu       = 4
    memory_gb = 16
    labels    = { "tier" = "high-mem" }
    taints    = [{ key = "tier", value = "high-mem", effect = "NoSchedule" }]
  },

  # Storage pool — for databases / PVCs
  {
    name      = "storage"
    role      = "worker"
    count     = 1
    cpu       = 2
    memory_gb = 8
    labels    = { "tier" = "storage" }
    taints    = [{ key = "tier", value = "storage", effect = "NoSchedule" }]
  },
]
```

**Scheduling a Pod on the `fat` pool:**

```yaml
tolerations:
  - key: tier
    value: high-mem
    effect: NoSchedule
nodeSelector:
  tier: high-mem
```

**Scheduling on ANY untainted node (ignore the tainted pools):**  
Just don't add a toleration — Kubernetes will never place the Pod on tainted nodes.

---

### 6 · Workers with labels only (soft affinity, no taint)

Labels without taints allow you to *prefer* certain nodes without *forcing* it.  
Pods without an affinity rule can still land on any node.

```hcl
node_pools = [
  { name = "cp",   role = "controlplane", count = 3, cpu = 2, memory_gb = 4 },
  {
    name      = "ssd"
    role      = "worker"
    count     = 2
    cpu       = 2
    memory_gb = 4
    labels    = { "disk-type" = "ssd" }
    # no taints — other Pods can still land here
  },
  { name = "hdd", role = "worker", count = 2, cpu = 2, memory_gb = 4,
    labels = { "disk-type" = "hdd" } },
]
```

**Targeting with nodeSelector (hard):**
```yaml
nodeSelector:
  disk-type: ssd
```

**Targeting with affinity (soft — prefer SSD but fall back):**
```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
            - key: disk-type
              operator: In
              values: [ssd]
```

---

## Generated VM names and MACs

| Pool index | Pool name | Node | VM name | MAC |
|---|---|---|---|---|
| 0 | `cp` | 1 | `cp-1` | `c6:21:11:aa:00:01` |
| 0 | `cp` | 2 | `cp-2` | `c6:21:11:aa:00:02` |
| 1 | `worker` | 1 | `worker-1` | `c6:21:11:aa:01:01` |
| 1 | `worker` | 2 | `worker-2` | `c6:21:11:aa:01:02` |
| 2 | `storage` | 1 | `storage-1` | `c6:21:11:aa:02:01` |

MACs are deterministic — same `tfvars` always produces the same MAC, so ARP-based IP discovery is stable across reboots and re-applies.

> ⚠️ Renaming or reordering pools changes their index → changes their MACs → Terraform destroys and recreates those VMs. Rename pools only intentionally.

---

## Variable reference

| Variable | Type | Default | Description |
|---|---|---|---|
| `node_pools` | `list(object)` | 3 CP + 3 workers | Node pool definitions |
| `allow_scheduling_on_controlplane` | `bool` | `false` | Remove CP taint — allow workloads on CPs |

### node_pools object fields

| Field | Required | Description |
|---|---|---|
| `name` | ✅ | Pool name prefix (e.g. `cp`, `worker`) |
| `role` | ✅ | `controlplane` or `worker` |
| `count` | ✅ | Number of VMs in this pool |
| `cpu` | ✅ | vCPUs per VM |
| `memory_gb` | ✅ | RAM in GiB per VM |
| `labels` | ➖ | `map(string)` — Kubernetes node labels |
| `taints` | ➖ | List of `{ key, value, effect }` — Kubernetes node taints |

### Taint effects

| Effect | Behaviour |
|---|---|
| `NoSchedule` | New Pods without a matching toleration are never scheduled here |
| `PreferNoSchedule` | Kubernetes avoids scheduling here but will if no other option |
| `NoExecute` | Existing Pods without toleration are evicted; new Pods not scheduled |
