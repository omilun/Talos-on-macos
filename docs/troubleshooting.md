# Troubleshooting

## VM fails to boot

```bash
tart list        # see VM states
tart stop <vm>   # stop a stuck VM
tart delete <vm> # delete and let Terraform recreate it
```

## Flux not reconciling

```bash
flux get all -A
flux logs --all-namespaces
flux reconcile kustomization flux-system --with-source
```

See [gitops.md](gitops.md) for full Flux debugging steps.

## Gateway has no LoadBalancer IP

```bash
kubectl get ciliumloadbalancerippool
kubectl get ciliuml2announcementpolicy
cilium status
```

## Certificate not Ready

```bash
kubectl get certificate -n networking
kubectl describe certificate wildcard-cluster-tls -n networking
kubectl logs -n cert-manager deploy/cert-manager
```

## Browser shows "Not Secure"

```bash
# Verify CA is trusted
security find-certificate -c "Talos" /Library/Keychains/System.keychain

# Re-run trust script if needed
bash scripts/trust-ca.sh
```

Restart your browser after trusting the CA.

## DNS not resolving

```bash
cat /etc/resolver/talos-on-macos.com
dig @192.168.64.x -p 30053 argocd.talos-tart-ha.talos-on-macos.com
scutil --dns | grep talos
sudo dscacheutil -flushcache
```

---

## Argo Events: webhook not triggering

**Symptom:** push to GitHub, no Workflow appears in Argo Workflows UI.

```bash
# 1. Check EventSource pod is running
kubectl -n argo get pods | grep eventsource

# 2. Check EventSource logs for incoming requests
kubectl -n argo logs -l eventsource-name=pulse-github --tail=50

# 3. Check Sensor logs for trigger activity
kubectl -n argo logs -l sensor-name=pulse-ci --tail=50

# 4. Verify EventBus (NATS) is running
kubectl -n argo get pods | grep eventbus
```

**HMAC validation failing** (`invalid signature` in EventSource logs):
- The webhook secret in GitHub must match the `github-webhook-secret` Kubernetes secret
- Verify: `kubectl -n argo get secret github-webhook-secret -o jsonpath='{.data.secret}' | base64 -d`
- Update the GitHub webhook secret at: repo → Settings → Webhooks → Edit

**Sensor filter not matching** (`no dependency matched` in Sensor logs):
- The Sensor filters on `body.ref = refs/heads/main` — pushes to other branches are ignored by design
- Check the filter in `gitops/apps/pulse/ci/sensor.yaml`

**Endpoint not reachable from GitHub:**
```bash
# Test the endpoint is accessible
curl -I https://events.talos-tart-ha.talos-on-macos.com/pulse/push
# Should return 405 (Method Not Allowed) — means it's reachable, POST only
```

---

## BuildKit: daemon not starting

```bash
kubectl -n buildkit get pods
kubectl -n buildkit describe pod -l app=buildkitd
kubectl -n buildkit logs deploy/buildkitd
```

**Common causes:**
- `MountVolume.SetUp failed: secret "registry-credentials" not found` — Zot has no auth, this secret is optional. The volume is marked `optional: true` in the deployment; if you see this error, check the deployment spec has `optional: true` on the secret volume.
- `readiness probe failed` — probe must use `buildctl --addr tcp://localhost:1234 debug workers` (not the unix socket default)
- Privileged pod not scheduling — verify the `buildkit` namespace has `pod-security.kubernetes.io/enforce: privileged`

**Test buildkitd manually:**
```bash
kubectl -n buildkit exec deploy/buildkitd -- buildctl --addr tcp://localhost:1234 debug workers
```

---

## BuildKit: image build or push fails

Check the Argo Workflows UI for the failed step logs, or:

```bash
# Find the failed workflow pod
kubectl -n argo get pods | grep pulse-build

# Get logs from the build step
kubectl -n argo logs <pod-name> -c main
```

**Push to Zot fails** (`unauthorized` or `connection refused`):
- Zot has no authentication — if you see `unauthorized`, check the Zot config
- Verify Zot is running: `kubectl -n registry get pods`
- Test push from inside cluster: `kubectl -n buildkit exec deploy/buildkitd -- buildctl --addr tcp://localhost:1234 build --frontend dockerfile.v0 --opt context=... --output ...`

---

## ArgoCD: app OutOfSync or SyncError

```bash
# Check app status
kubectl -n argocd get application

# Get detailed sync status
kubectl -n argocd describe application pulse-ci
```

**`one or more synchronization tasks are not valid` (circular ownership):**
- An ArgoCD Application is trying to sync its own `Application` object (which Flux owns)
- Fix: remove `argocd-app.yaml` from the ArgoCD-managed kustomization; only Flux's kustomization should include it

**`ClusterRole / ClusterRoleBinding not permitted`:**
- The `AppProject` `clusterResourceWhitelist` is missing these kinds
- Fix: add them to `gitops/apps/project.yaml`

**App stuck in `Progressing`:**
```bash
kubectl -n argocd logs deploy/argocd-application-controller | grep -i error | tail -20
```

---

## Zot Registry: checking stored images

```bash
# Open the Zot web UI
open https://registry.talos-tart-ha.talos-on-macos.com

# List repositories via API
curl -s https://registry.talos-tart-ha.talos-on-macos.com/v2/_catalog | python3 -m json.tool

# List tags for a repo
curl -s https://registry.talos-tart-ha.talos-on-macos.com/v2/pulse/auth-service/tags/list | python3 -m json.tool
```

**Pull an image:**
```bash
docker pull registry.talos-tart-ha.talos-on-macos.com/pulse/auth-service:sha-abc1234
```

> Zot has no authentication. No `docker login` needed.

---

## Flux: KS stuck in "Reconciliation in progress"

```bash
kubectl -n flux-system describe kustomization infrastructure | tail -20
```

**Cause:** Flux is running health checks and a Deployment/StatefulSet is not becoming `Ready`.
The health check timeout is **15 minutes**.

Find the unhealthy resource:
```bash
kubectl get pods -A | grep -v Running | grep -v Completed
```

Common fixes:
- Missing Secret a pod depends on → create the secret, or mark the volume `optional: true`
- Wrong readiness probe → fix the probe, patch the Deployment directly to unblock, then fix in git
- CRD not installed yet → check `dependsOn` ordering in `gitops/infrastructure/kustomization.yaml`

**Force re-check after fixing:**
```bash
kubectl -n flux-system annotate kustomization infrastructure \
  reconcile.fluxcd.io/requestedAt="$(date -u +%FT%TZ)" --overwrite
```

---

## Full reset

```bash
tofu destroy
sudo rm -f /etc/resolver/talos-on-macos.com
sudo dscacheutil -flushcache
# Optionally remove downloaded image:
rm -f ~/Downloads/metal-arm64.raw
```

