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

## Full reset

```bash
tofu destroy
sudo rm -f /etc/resolver/talos-on-macos.com
sudo dscacheutil -flushcache
# Optionally remove downloaded image:
rm -f ~/Downloads/metal-arm64.raw
```
