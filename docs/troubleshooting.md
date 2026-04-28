# Troubleshooting

Common issues and solutions for Talos on macOS.

## Provisioning Issues

### Terraform apply hangs during Talos installation

**Symptom**: Stuck at "Waiting for Talos API..." for >10 minutes.

**Causes**:
- VM didn't boot from disk image
- Network connectivity issue between host and VMs
- Talos API not responding

**Solutions**:
1. Check VM status:
   ```bash
   tart list
   # Should show all 6 VMs as running
   ```

2. Manually check a VM:
   ```bash
   talosctl -n 192.168.64.101 status
   ```

3. If stuck, restart the VM:
   ```bash
   # Stop VM
   tart stop talos-cp1
   # Start again
   tart run talos-cp1
   ```

4. Re-run Terraform:
   ```bash
   tofu apply
   ```

### NVRAM seed file not found

**Symptom**: Error like `nvram-arm64.bin: no such file or directory`.

**Solution**:
- Ensure `nvram_path` in `terraform.tfvars` points to the correct location
- Extract from existing Tart VM:
  ```bash
  cp ~/.tart/vms/<any-vm>/nvram clusters/cluster1/nvram-arm64.bin
  ```

### Disk image not found

**Symptom**: Error like `metal-arm64.raw: no such file or directory`.

**Solution**:
- Download from [factory.talos.dev](https://factory.talos.dev)
- Update `talos_disk_image_path` in `terraform.tfvars` to match location
- Default expects: `~/Downloads/metal-arm64.raw`

### SSH key authentication fails

**Symptom**: `Error generating SSH key` or permission denied.

**Solution**:
- Check `~/.ssh` directory exists and has correct permissions:
  ```bash
  chmod 700 ~/.ssh
  ```
- Delete any corrupted keys:
  ```bash
  rm ~/.ssh/talos_*
  ```
- Re-run `tofu apply` to generate new keys

---

## Kubernetes Issues

### Nodes stuck in NotReady

**Symptom**: `kubectl get nodes` shows NotReady or Unknown.

**Causes**:
- Cilium not ready
- API server not responding
- Network connectivity issues

**Solutions**:

1. Check node status:
   ```bash
   kubectl describe node <node-name>
   kubectl get events --sort-by='.lastTimestamp' -A
   ```

2. Check Cilium:
   ```bash
   kubectl get pod -n kube-system -l k8s-app=cilium
   # Should be all Running
   ```

3. If Cilium is down, check logs:
   ```bash
   kubectl logs -n kube-system <cilium-pod>
   ```

4. Restart a stuck node:
   ```bash
   talosctl -n 192.168.64.101 reboot
   kubectl wait --for=condition=Ready node/<node-name> --timeout=300s
   ```

### DNS not working

**Symptom**: `kubectl run -it --rm debug --image=busybox -- nslookup google.com` fails.

**Causes**:
- CoreDNS not running
- Cilium DNS policy blocking

**Solutions**:

1. Check CoreDNS:
   ```bash
   kubectl get deployment -n kube-system coredns
   kubectl logs -n kube-system -l k8s-app=kube-dns
   ```

2. Restart CoreDNS:
   ```bash
   kubectl rollout restart deployment -n kube-system coredns
   ```

3. Check Cilium NetworkPolicy:
   ```bash
   kubectl get networkpolicy -A
   # If any exists, temporarily delete to test:
   kubectl delete networkpolicy -A --all
   ```

### Pod stuck in Pending

**Symptom**: `kubectl get pod` shows Pending status.

**Causes**:
- No available node (CPU/memory)
- Persistent Volume Claim not bound
- NodeSelector/Affinity constraints

**Solutions**:

1. Check why:
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   # Look for Events section
   ```

2. Check node capacity:
   ```bash
   kubectl top nodes
   kubectl top pod -A
   ```

3. If quota exceeded, scale down other pods or add more workers:
   ```bash
   # Increase workers
   # Edit terraform.tfvars: worker_count = 5
   tofu apply
   ```

---

## Flux Issues

### HelmRelease CRD not found

**Symptom**: Error like `no matches for kind "HelmRelease"`.

**Causes**:
- Flux Helm controller not installed
- CRD not applied yet

**Solutions**:

1. Check Flux installation:
   ```bash
   kubectl get pod -n flux-system
   # helm-controller should be Running
   ```

2. Wait for CRDs:
   ```bash
   kubectl wait --for condition=established --timeout=300s crd/helmreleases.helm.toolkit.fluxcd.io
   ```

3. Check Kustomization order:
   ```bash
   flux get kustomization
   # Should show infrastructure first, then apps
   ```

### Flux reconciliation failed

**Symptom**: `flux get kustomization` shows Reconciling:Failed.

**Solutions**:

1. Check status:
   ```bash
   flux get kustomization flux-system -v
   ```

2. Check git sync:
   ```bash
   flux get source git flux-system
   # Should show "ready"
   ```

3. If git auth issue:
   ```bash
   kubectl get secret -n flux-system flux-system -o yaml
   # Verify SSH key is correct
   ```

4. Manually reconcile:
   ```bash
   flux reconcile source git flux-system
   flux reconcile kustomization flux-system
   ```

5. Check pod logs:
   ```bash
   kubectl logs -n flux-system -l app=kustomize-controller -f
   kubectl logs -n flux-system -l app=helm-controller -f
   ```

### HelmRelease stuck in degraded state

**Symptom**: `kubectl get helmrelease -A` shows Degraded or Reconciling.

**Causes**:
- Helm chart version not found
- Values error (invalid YAML)
- Chart dependencies missing

**Solutions**:

1. Check status:
   ```bash
   kubectl describe helmrelease <name> -n <namespace>
   ```

2. Check HelmRepository:
   ```bash
   kubectl get helmrepository -A
   flux get source helm
   ```

3. Manually debug Helm:
   ```bash
   helm repo update
   helm get values <release> -n <namespace>
   helm history <release> -n <namespace>
   ```

4. Check values YAML syntax:
   ```bash
   kubectl get helmrelease <name> -n <namespace> -o yaml
   # Inspect spec.values
   ```

5. If chart issue, edit HelmRelease version:
   ```bash
   kubectl edit helmrelease <name> -n <namespace>
   # Change spec.chart.spec.version
   ```

---

## Cilium Issues

### Network connectivity broken

**Symptom**: Pods can't reach external services or each other.

**Causes**:
- Cilium networking misconfiguration
- Gateway API not installed
- Network policy blocking traffic

**Solutions**:

1. Check Cilium status:
   ```bash
   kubectl exec -n kube-system <cilium-pod> -- cilium status
   ```

2. Check Cilium logs:
   ```bash
   kubectl logs -n kube-system <cilium-pod> -c cilium
   ```

3. Check IP routing:
   ```bash
   kubectl exec -n kube-system <cilium-pod> -- ip route
   ```

4. Check NetworkPolicy rules:
   ```bash
   kubectl get networkpolicy -A
   kubectl exec -n kube-system <cilium-pod> -- cilium policy list
   ```

5. Test Pod-to-Pod connectivity:
   ```bash
   kubectl run -it --rm debug --image=busybox -- sh
   # Inside pod: ping <other-pod-ip>
   ```

---

## cert-manager Issues

### ClusterIssuer stuck in "pending"

**Symptom**: `kubectl get clusterissuer` shows Pending.

**Causes**:
- cert-manager CRDs not installed
- cert-manager pod not running
- cert-manager HelmRelease failed

**Solutions**:

1. Check cert-manager:
   ```bash
   kubectl get pod -n cert-manager
   # Should be Running
   ```

2. Check ClusterIssuer status:
   ```bash
   kubectl describe clusterissuer <issuer-name>
   ```

3. Check HelmRelease:
   ```bash
   kubectl describe helmrelease cert-manager -n kube-system
   # or wherever it's deployed
   ```

4. Restart cert-manager:
   ```bash
   kubectl rollout restart deployment -n cert-manager cert-manager
   ```

### Certificate not issued

**Symptom**: `kubectl get certificate -A` shows one Pending.

**Causes**:
- Issuer not ready
- ACME challenge not passed (if using ACME)
- DNS not configured

**Solutions**:

1. Check Certificate:
   ```bash
   kubectl describe certificate <cert-name>
   ```

2. Check order/challenge status:
   ```bash
   kubectl get order -A
   kubectl get challenge -A
   ```

3. Check logs:
   ```bash
   kubectl logs -n cert-manager <cert-manager-pod>
   ```

4. For ACME, ensure DNS is correct:
   ```bash
   nslookup <domain>
   # Should resolve
   ```

---

## Loki Issues

### Loki pod crashing (OOMKilled)

**Symptom**: `kubectl get pod -n monitoring loki-*` shows CrashLoopBackOff.

**Cause**: Loki requires writable `/var/loki` but Talos enforces read-only root filesystem.

**Solution** (already applied in GitOps):

Loki HelmRelease should include:

```yaml
spec:
  values:
    loki:
      config:
        common:
          replication_factor: 1
      storage:
        type: filesystem
    persistence:
      enabled: true
      emptyDir: {}  # or PVC
```

This provides `/var/loki` as emptyDir to bypass read-only constraint.

If still crashing, check:

```bash
kubectl logs -n monitoring <loki-pod>
```

### Logs not appearing in Loki

**Symptom**: No logs in Grafana Loki datasource.

**Causes**:
- Promtail not running
- Promtail config not scraping kubelet
- Network connectivity from worker nodes

**Solutions**:

1. Check Promtail:
   ```bash
   kubectl get daemonset -n monitoring
   # promtail should be deployed
   kubectl get pod -n monitoring -l app=promtail
   ```

2. Check Promtail logs:
   ```bash
   kubectl logs -n monitoring <promtail-pod> -c promtail
   ```

3. Check Promtail config:
   ```bash
   kubectl get configmap -n monitoring promtail-config -o yaml
   ```

4. Manually test Loki endpoint:
   ```bash
   kubectl port-forward -n monitoring svc/loki 3100:3100
   curl http://localhost:3100/loki/api/v1/label
   # Should return {"status":"success","data":["__name__","job",...]}
   ```

---

## Performance Issues

### High CPU/Memory usage

**Symptom**: `kubectl top nodes` shows nodes near 100%.

**Solutions**:

1. Check what's using resources:
   ```bash
   kubectl top pod -A --sort-by=memory
   ```

2. Scale down non-essential services (Prometheus, Grafana):
   ```bash
   kubectl scale deployment -n monitoring prometheus --replicas=0
   ```

3. Add more workers:
   ```bash
   # Edit terraform.tfvars: worker_count = 5
   tofu apply
   ```

### Slow API response

**Symptom**: `kubectl get pod` takes >5 seconds.

**Causes**:
- etcd overload
- API server GC pause
- Network latency

**Solutions**:

1. Check etcd health:
   ```bash
   kubectl exec -n kube-system <etcd-pod> -- etcdctl endpoint status
   ```

2. Check API server logs:
   ```bash
   kubectl logs -n kube-system <api-server-pod>
   ```

3. Restart API server:
   ```bash
   kubectl delete pod -n kube-system <api-server-pod>
   # Kubernetes will restart it
   ```

---

## General Debugging

### Check all pod statuses

```bash
kubectl get pod -A
# Any CrashLoopBackOff, Pending, or Error?
```

### Check node logs

```bash
export TALOSCONFIG=_out/talosconfig
talosctl -n <ip> logs kubelet | tail -100
talosctl -n <ip> logs containerd | tail -100
```

### Flush DNS cache (macOS)

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

### Check Tart VM status

```bash
tart list
tart show <vm-name>
```

### Rebuild kubeconfig if corrupted

```bash
# Backup old one
cp _out/kubeconfig.yaml _out/kubeconfig.yaml.bak
# Regenerate
tofu taint null_resource.kubeconfig
tofu apply
```

---

## Getting Help

1. Check this document
2. Check [Getting Started](getting-started.md) and [Usage](usage.md)
3. Check Talos logs: `talosctl logs`
4. Check Kubernetes events: `kubectl get events -A`
5. Check GitHub Issues: https://github.com/omilun/Talos-on-macos/issues
6. Open an issue with logs attached

---

## Reporting Issues

When reporting, include:

```bash
# Cluster info
kubectl get nodes
kubectl get pod -A

# Events
kubectl get events -A --sort-by='.lastTimestamp' | tail -50

# Flux status
flux get all -A

# Terraform output
tofu output

# Specific pod logs (if applicable)
kubectl logs -n <namespace> <pod-name>

# Talos logs (if VM issue)
talosctl -n <ip> logs <service>
```
