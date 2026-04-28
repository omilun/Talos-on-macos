# Cluster2 Template

This is a template directory for deploying a second independent Talos Kubernetes cluster.

## Setup

To use this template:

1. **Copy from cluster1** (already done if you cloned this repo):

   ```bash
   cp -r ../cluster1 ../cluster2
   ```

2. **Configure**:

   ```bash
   cd ../cluster2/bootstrap/terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with unique cluster name
   sed -i '' 's/cluster_name = "tart-lab"/cluster_name = "cluster2"/g' terraform.tfvars
   ```

3. **Deploy**:

   ```bash
   tofu apply
   ```

## Key Differences from cluster1

Configure these in `terraform.tfvars`:

| Setting | Purpose |
|---------|---------|
| `cluster_name` | Must be unique (e.g., "cluster2", "staging", "dev") |
| `talos_version` | Can differ (e.g., v1.14.0 while cluster1 uses v1.13.0) |
| `kubernetes_version` | Can differ for testing upgrades |
| `flux_repository_branch` | Can sync different git branch (e.g., "cluster2-main") |

Example:

```hcl
cluster_name           = "cluster2"
talos_version          = "v1.14.0"
kubernetes_version     = "v1.36.0"
flux_repository_branch = "cluster2-main"
```

## Network isolation

Each cluster gets a unique subnet (configured by `cluster_name`). VMs are isolated from other clusters.

## GitOps configuration

Update `flux_repository_branch` to sync a separate git branch or repo:

```hcl
flux_repository_branch = "cluster2-prod"
```

Then manage cluster2 apps separately:

```bash
git checkout -b cluster2-prod
# Edit gitops/ for cluster2 specifics
git push origin cluster2-prod
```

Flux will sync cluster2 to this branch.

## Multi-cluster management

Access both clusters:

```bash
export KUBECONFIG=\
  ../cluster1/_out/kubeconfig.yaml:\
  ../cluster2/_out/kubeconfig.yaml

kubectl config get-contexts
kubectl config use-context cluster2
```

## Cleanup

Destroy cluster2:

```bash
cd bootstrap/terraform
tofu destroy
```

Delete the directory (or keep for re-deployment):

```bash
cd ../../../
rm -rf cluster2
```

---

For more details, see [cluster1/README.md](../cluster1/README.md) and the main [README.md](../../README.md).
