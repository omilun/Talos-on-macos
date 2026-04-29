#!/usr/bin/env bash
# scripts/trust-ca.sh
#
# Trusts the tart-lab Root CA from the Talos-on-mac cluster on macOS.
# Safe to run multiple times (idempotent).
#
# Usage:
#   bash scripts/trust-ca.sh                         # interactive (opens GUI via mobileconfig)
#   bash scripts/trust-ca.sh --non-interactive       # headless / CI / Ansible / Terraform
#   bash scripts/trust-ca.sh --generate-only         # only regenerate mobileconfig, don't install
#
# Automation examples:
#   Ansible:   - command: bash scripts/trust-ca.sh --non-interactive
#   Terraform: provisioner "local-exec" { command = "bash scripts/trust-ca.sh --non-interactive" }
#
# Requirements:
#   - kubectl in PATH with valid KUBECONFIG
#   - macOS (uses `security` and `open` commands)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILECONFIG="${REPO_ROOT}/setup-trust.mobileconfig"
CA_CERT_TMP="/tmp/tart-lab-root-ca.crt"
CA_NAME="tart-lab Root CA"
MODE="${1:-interactive}"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}✅${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠️ ${NC} $*"; }
error()   { echo -e "${RED}❌${NC} $*" >&2; }

# ── sudo password resolution ─────────────────────────────────────────────────
if [ -f "${REPO_ROOT}/.env" ]; then
  # shellcheck disable=SC1091
  set -o allexport; source "${REPO_ROOT}/.env"; set +o allexport
fi
if [ -z "${SUDO_PASSWORD:-}" ] && [[ "${MODE}" == "--non-interactive" ]]; then
  read -rs -p "macOS sudo password (for CA trust): " SUDO_PASSWORD
  echo ""
fi
run_sudo() { echo "${SUDO_PASSWORD:-}" | sudo -S "$@" 2>/dev/null; }

# ── check if already trusted ─────────────────────────────────────────────────
already_trusted() {
  security find-certificate -c "$CA_NAME" /Library/Keychains/System.keychain \
    &>/dev/null
}

if already_trusted; then
  info "CA '${CA_NAME}' is already trusted in System Keychain."
  exit 0
fi

echo "=== Talos-on-mac: Cluster CA Trust Setup ==="
echo ""

# ── extract CA cert from cluster ──────────────────────────────────────────────
if ! kubectl get secret root-ca-secret -n cert-manager \
     -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > "${CA_CERT_TMP}"; then
  error "Could not fetch CA cert. Is kubectl configured and the cluster running?"
  echo "   Run: export KUBECONFIG=/path/to/kubeconfig.yaml"
  exit 1
fi
info "CA cert extracted from cluster"

# ── regenerate mobileconfig from live CA cert ─────────────────────────────────
CA_B64=$(base64 -i "${CA_CERT_TMP}" | tr -d '\n')

cat > "${MOBILECONFIG}" << MCONFIG
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadCertificateFileName</key>
            <string>tart-lab-root-ca.crt</string>
            <key>PayloadContent</key>
            <data>${CA_B64}</data>
            <key>PayloadDescription</key>
            <string>Adds the tart-lab Root CA so your browser trusts https://*.talos-tart-ha.talos-on-macos.com</string>
            <key>PayloadDisplayName</key>
            <string>tart-lab Root CA (Talos-on-mac cluster)</string>
            <key>PayloadIdentifier</key>
            <string>com.talos-on-macos.tart-lab.ca</string>
            <key>PayloadType</key>
            <string>com.apple.security.root</string>
            <key>PayloadUUID</key>
            <string>A1B2C3D4-E5F6-7890-ABCD-EF1234567890</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
    </array>
    <key>PayloadDescription</key>
    <string>Trusts the tart-lab private Root CA. After installing, all HTTPS dashboards show a green padlock.</string>
    <key>PayloadDisplayName</key>
    <string>Talos-on-mac Cluster CA Trust</string>
    <key>PayloadIdentifier</key>
    <string>com.talos-on-macos.ca-trust</string>
    <key>PayloadOrganization</key>
    <string>talos-on-macos</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>B2C3D4E5-F6A7-8901-BCDE-F12345678901</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
MCONFIG

info "setup-trust.mobileconfig regenerated from live cluster CA"

if [[ "${MODE}" == "--generate-only" ]]; then
  echo ""
  echo "Mobileconfig written to: ${MOBILECONFIG}"
  echo "Double-click it to install in macOS System Settings."
  exit 0
fi

# ── install ────────────────────────────────────────────────────────────────────
if [[ "${MODE}" == "--non-interactive" ]]; then
  # Headless mode: direct Keychain install (requires sudo)
  echo "Installing CA into System Keychain (requires sudo)..."
  run_sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain "${CA_CERT_TMP}"
  info "CA trusted in System Keychain (headless mode)"
else
  # Interactive mode: open the friendly macOS GUI installer
  echo ""
  echo "  ┌─────────────────────────────────────────────────────┐"
  echo "  │  macOS will open System Settings → Privacy & Security │"
  echo "  │  Click 'Install...' and enter your password.          │"
  echo "  │  This is safe — it only trusts this cluster's CA.     │"
  echo "  └─────────────────────────────────────────────────────┘"
  echo ""
  open "${MOBILECONFIG}"
  echo ""
  warn "After clicking Install, re-run this script to verify:"
  echo "  bash scripts/trust-ca.sh"
fi

# ── verify ─────────────────────────────────────────────────────────────────────
sleep 2
if already_trusted; then
  echo ""
  info "CA '${CA_NAME}' is now trusted. Testing HTTPS..."
  DOMAIN="talos-tart-ha.talos-on-macos.com"
  for svc in argocd grafana prometheus; do
    code=$(curl -s -o /dev/null -w "%{http_code}" \
      https://${svc}.${DOMAIN}/ 2>/dev/null || echo "000")
    if [[ "$code" != "000" ]]; then
      info "https://${svc}.${DOMAIN} → HTTP ${code} 🔒"
    else
      warn "https://${svc}.${DOMAIN} → not reachable (DNS configured?)"
    fi
  done
fi
