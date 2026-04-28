#!/usr/bin/env bash
# delete-vm.sh — Stop (if running) and delete a single Tart VM.
#
# Required environment variables:
#   VM_NAME   Name of the VM to delete

set -euo pipefail

: "${VM_NAME:?}"

log() { echo "[INFO]  $*" >&2; }
ok()  { echo "[OK]    $*" >&2; }

if ! tart list 2>/dev/null | awk '{print $2}' | grep -qx "$VM_NAME"; then
  log "VM $VM_NAME does not exist — nothing to delete"
  exit 0
fi

# Stop if running
if tart list 2>/dev/null | awk '{print $1, $2}' | grep -qE "Running $VM_NAME"; then
  log "Stopping $VM_NAME..."
  tart stop "$VM_NAME" 2>/dev/null || true
  sleep 3
fi

log "Deleting $VM_NAME..."
tart delete "$VM_NAME" 2>/dev/null || true

ok "VM $VM_NAME deleted"
