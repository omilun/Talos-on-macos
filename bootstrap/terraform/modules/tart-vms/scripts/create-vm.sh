#!/usr/bin/env bash
# create-vm.sh — Create a single Tart VM from a Talos metal-arm64.raw image.
#
# Required environment variables:
#   VM_NAME      Name of the VM (e.g. talos-cp1)
#   VM_MAC       MAC address in colon-separated hex (e.g. c6:21:11:aa:bb:01)
#   VM_CPU       Number of vCPUs
#   VM_MEMORY    Memory in bytes
#   IMAGE_PATH   Path to metal-arm64.raw (expanded, no ~)
#   DISK_SIZE_GB Final disk size in GiB
#   TART_VMS_DIR Path to ~/.tart/vms
#   NVRAM_SRC    Path to nvram-arm64.bin seed file

set -euo pipefail

# Validate required env vars
: "${VM_NAME:?}"
: "${VM_MAC:?}"
: "${VM_CPU:?}"
: "${VM_MEMORY:?}"
: "${IMAGE_PATH:?}"
: "${DISK_SIZE_GB:?}"
: "${TART_VMS_DIR:?}"
: "${NVRAM_SRC:?}"

log()  { echo "[INFO]  $*" >&2; }
ok()   { echo "[OK]    $*" >&2; }
err()  { echo "[ERROR] $*" >&2; }

# ── Pre-flight checks ─────────────────────────────────────────────────────────

if ! command -v tart &>/dev/null; then
  err "tart not found. Install from https://tart.run"
  exit 1
fi

if [[ ! -f "$IMAGE_PATH" ]]; then
  err "Talos image not found: $IMAGE_PATH"
  err "Download: curl -L -o '$IMAGE_PATH' \$(scripts/01-download-image.sh --print-url)"
  exit 1
fi

if [[ ! -f "$NVRAM_SRC" ]]; then
  err "NVRAM seed not found: $NVRAM_SRC"
  err "Expected: nvram-arm64.bin in the repository root."
  exit 1
fi

# ── Idempotency: skip if already exists ───────────────────────────────────────

if tart list 2>/dev/null | awk '{print $2}' | grep -qx "$VM_NAME"; then
  log "VM $VM_NAME already exists — skipping creation"
  exit 0
fi

# ── Create VM ─────────────────────────────────────────────────────────────────

log "Creating VM: $VM_NAME  cpu=$VM_CPU  mem=$((VM_MEMORY / 1024 / 1024 / 1024))GiB  mac=$VM_MAC"

vm_dir="$TART_VMS_DIR/$VM_NAME"
mkdir -p "$vm_dir"

# Tart Linux VM config
cat > "$vm_dir/config.json" <<JSON
{
  "version": 1,
  "os": "linux",
  "arch": "arm64",
  "cpuCount": ${VM_CPU},
  "cpuCountMin": 1,
  "memorySize": ${VM_MEMORY},
  "memorySizeMin": 1073741824,
  "macAddress": "${VM_MAC}",
  "diskFormat": "raw",
  "display": {"width": 1024, "height": 768}
}
JSON

# Copy Talos image and sparse-extend to DISK_SIZE_GB
log "Copying and extending disk image to ${DISK_SIZE_GB} GiB..."
cp "$IMAGE_PATH" "$vm_dir/disk.img"
dd if=/dev/zero bs=1 count=0 seek=$((DISK_SIZE_GB * 1024 * 1024 * 1024)) \
   of="$vm_dir/disk.img" 2>/dev/null

# EFI NVRAM (required for Apple VZ Linux boot)
cp "$NVRAM_SRC" "$vm_dir/nvram.bin"

ok "VM $VM_NAME created at $vm_dir"
