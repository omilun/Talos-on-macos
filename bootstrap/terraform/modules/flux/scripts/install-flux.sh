#!/usr/bin/env bash
# install-flux.sh — Bootstrap Flux v2 into the Talos cluster.
#
# Steps:
#   1. Install/upgrade the flux CLI binary
#   2. Run pre-flight checks (flux check --pre)
#   3. Install Flux controllers (flux install)
#   4. If FLUX_GIT_REPOSITORY_URL is set, configure the GitRepository source
#      and Kustomization pointing at the gitops/ directory
#
# Required env vars: KUBECONFIG
# Optional env vars:
#   FLUX_VERSION             — specific version; defaults to latest stable
#   FLUX_GIT_REPOSITORY_URL  — e.g. https://github.com/omilun/talos-on-macos
#   FLUX_GIT_BRANCH          — default: main
#   FLUX_GIT_PATH            — default: gitops/clusters/tart-lab
#   GITHUB_TOKEN             — personal access token (for private repos / github bootstrap)

set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG is required}"

FLUX_VERSION="${FLUX_VERSION:-}"
FLUX_GIT_REPOSITORY_URL="${FLUX_GIT_REPOSITORY_URL:-}"
FLUX_GIT_BRANCH="${FLUX_GIT_BRANCH:-main}"
FLUX_GIT_PATH="${FLUX_GIT_PATH:-gitops/clusters/tart-lab}"

log() { echo "[INFO]  $*" >&2; }
ok()  { echo "[OK]    $*" >&2; }
err() { echo "[ERROR] $*" >&2; exit 1; }

# ── 1. Install flux CLI ───────────────────────────────────────────────────────
if ! command -v flux &>/dev/null || [[ -n "${FLUX_VERSION}" && "$(flux version --client -o json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["flux"])' 2>/dev/null || echo '')" != "${FLUX_VERSION}" ]]; then
  log "Installing flux CLI${FLUX_VERSION:+ version ${FLUX_VERSION}}..."
  if command -v brew &>/dev/null; then
    brew install fluxcd/tap/flux 2>/dev/null || brew upgrade fluxcd/tap/flux 2>/dev/null || true
  else
    INSTALL_URL="https://fluxcd.io/install.sh"
    if [[ -n "${FLUX_VERSION}" ]]; then
      export FLUX_VERSION
    fi
    curl -s "${INSTALL_URL}" | bash
  fi
fi

flux_cli_version=$(flux version --client 2>/dev/null | awk '{print $NF}')
log "flux CLI: ${flux_cli_version}"

# ── 2. Pre-flight checks ──────────────────────────────────────────────────────
log "Running Flux pre-flight checks..."
flux check --pre || err "Flux pre-flight checks failed. Ensure the cluster is reachable and has sufficient resources."

# ── 3. Install Flux controllers ───────────────────────────────────────────────
log "Installing Flux controllers into flux-system namespace..."
flux install \
  --namespace=flux-system \
  --network-policy=true \
  --components=source-controller,kustomize-controller,helm-controller,notification-controller \
  --log-level=info

log "Waiting for Flux controllers to be ready..."
kubectl rollout status deployment/source-controller      -n flux-system --timeout=3m
kubectl rollout status deployment/kustomize-controller   -n flux-system --timeout=3m
kubectl rollout status deployment/helm-controller        -n flux-system --timeout=3m
kubectl rollout status deployment/notification-controller -n flux-system --timeout=3m
ok "Flux controllers running"

# ── 4. Configure GitRepository source + Kustomization ────────────────────────
if [[ -z "${FLUX_GIT_REPOSITORY_URL}" ]]; then
  log "FLUX_GIT_REPOSITORY_URL not set — Flux controllers installed but no GitRepository configured."
  log "Configure later with:"
  log "  flux create source git flux-system \\"
  log "    --url=https://github.com/omilun/talos-on-macos \\"
  log "    --branch=main \\"
  log "    --interval=1m"
  exit 0
fi

log "Configuring GitRepository: ${FLUX_GIT_REPOSITORY_URL} (branch: ${FLUX_GIT_BRANCH})"

# ── 4a. Auto-create gitops/clusters/<name>/ entrypoint if missing ─────────────
# Each cluster needs infrastructure.yaml + apps.yaml under gitops/clusters/<name>/.
# If this is a new cluster name, create the files, commit, and push so Flux
# can reconcile them after bootstrap.
CLUSTER_NAME=$(basename "${FLUX_GIT_PATH}")
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
CLUSTER_DIR="${REPO_ROOT}/gitops/clusters/${CLUSTER_NAME}"

if [ ! -f "${CLUSTER_DIR}/infrastructure.yaml" ]; then
  log "Creating Flux entrypoint for cluster: ${CLUSTER_NAME}"
  mkdir -p "${CLUSTER_DIR}"

  cat > "${CLUSTER_DIR}/infrastructure.yaml" << INFRA
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./gitops/infrastructure
  prune: true
  wait: true
  timeout: 15m
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-config
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./gitops/infrastructure/cert-manager-config
  prune: true
  wait: true
  timeout: 10m
  dependsOn:
    - name: infrastructure
INFRA

  cat > "${CLUSTER_DIR}/apps.yaml" << APPS
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./gitops/apps
  prune: true
  dependsOn:
    - name: infrastructure
  timeout: 5m
APPS

  # Commit and push so Flux can read the files from GitHub
  if git -C "${REPO_ROOT}" status --porcelain | grep -q "${CLUSTER_NAME}"; then
    git -C "${REPO_ROOT}" add "${CLUSTER_DIR}/"
    git -C "${REPO_ROOT}" \
      -c user.name="${GIT_AUTHOR_NAME:-omilun}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-omilun@users.noreply.github.com}" \
      commit -m "feat: add Flux entrypoint for cluster ${CLUSTER_NAME}"
    git -C "${REPO_ROOT}" push origin HEAD
    ok "Flux entrypoint committed and pushed for cluster: ${CLUSTER_NAME}"
  else
    log "Flux entrypoint already committed for cluster: ${CLUSTER_NAME}"
  fi
fi

# Build flux source git args
GIT_ARGS=(
  --url="${FLUX_GIT_REPOSITORY_URL}"
  --branch="${FLUX_GIT_BRANCH}"
  --interval=1m
)

# Add credentials for private repos
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  GIT_ARGS+=(--username=git --password="${GITHUB_TOKEN}")
fi

flux create source git flux-system \
  --namespace=flux-system \
  "${GIT_ARGS[@]}"

log "Configuring Kustomization at path: ${FLUX_GIT_PATH}"
flux create kustomization flux-system \
  --namespace=flux-system \
  --source=GitRepository/flux-system \
  --path="${FLUX_GIT_PATH}" \
  --prune=true \
  --interval=5m \
  --wait=false

ok "Flux bootstrap complete"
log "Flux is now syncing from: ${FLUX_GIT_REPOSITORY_URL}"
log "Path: ${FLUX_GIT_PATH}"
log "Monitor with: flux get all -A"
log "Watch events: flux logs --all-namespaces --follow"
