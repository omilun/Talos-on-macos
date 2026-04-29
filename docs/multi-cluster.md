# Multi-cluster

You can run multiple independent clusters side by side on the same Mac.

## How it works

Each cluster gets a unique name that drives everything:

- VMs are named `<cluster_name>-cp-0`, `<cluster_name>-worker-0`, etc.
- The Talos VIP, LB IP range, and MAC addresses are derived from the cluster name
- Flux is bootstrapped pointing at `gitops/clusters/<cluster_name>/`
- `tofu apply` auto-creates `gitops/clusters/<cluster_name>/infrastructure.yaml` and `apps.yaml` if they do not exist

## Running a second cluster

```bash
cd bootstrap/terraform

# New workspace so state is isolated
tofu workspace new cluster2

cp terraform.tfvars.example terraform.tfvars.cluster2
# Edit: set cluster_name = "cluster2", adjust CPU/RAM if needed

tofu apply -var-file=terraform.tfvars.cluster2
```

Each cluster runs its own Cilium Gateway with its own LoadBalancer IP from the pool, and its own wildcard cert.

## Resource requirements

| Nodes | vCPU (default) | RAM (default) |
|---|---|---|
| 6 | 18 cores | 24 GB |

Reduce with `control_plane_cpu`, `worker_cpu`, `control_plane_memory_mb`, `worker_memory_mb` in `terraform.tfvars`.
