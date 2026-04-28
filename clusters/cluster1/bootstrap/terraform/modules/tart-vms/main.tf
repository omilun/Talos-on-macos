# ── Create one Tart VM per node ───────────────────────────────────────────────
# Each VM is a separate resource instance so Terraform can create/destroy
# individual VMs without affecting others.
resource "null_resource" "vm" {
  for_each = var.nodes

  triggers = {
    name      = each.key
    mac       = each.value.mac
    cpu       = each.value.cpu
    memory_gb = each.value.memory_gb
    disk_size = var.disk_size_gb
    image_md5 = fileexists(pathexpand(var.image_path)) ? filemd5(pathexpand(var.image_path)) : "missing"
  }

  provisioner "local-exec" {
    command     = "bash ${path.module}/scripts/create-vm.sh"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      VM_NAME      = each.key
      VM_MAC       = each.value.mac
      VM_CPU       = each.value.cpu
      VM_MEMORY    = each.value.memory_gb * 1024 * 1024 * 1024
      IMAGE_PATH   = pathexpand(var.image_path)
      DISK_SIZE_GB = var.disk_size_gb
      TART_VMS_DIR = pathexpand("~/.tart/vms")
      NVRAM_SRC    = var.nvram_src
    }
  }

  # Destroy provisioner: stop and delete the VM.
  # Runs before the resource is removed from state.
  provisioner "local-exec" {
    when    = destroy
    command = "bash ${path.module}/scripts/delete-vm.sh"
    environment = {
      VM_NAME = each.key
    }
  }
}

# ── Boot each VM (idempotent: skip if already running) ────────────────────────
resource "null_resource" "boot" {
  for_each   = var.nodes
  depends_on = [null_resource.vm]

  triggers = {
    vm_id = null_resource.vm[each.key].id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-BASH
      name="${each.key}"
      if tart list 2>/dev/null | awk '{print $1, $2}' | grep -qE "Running $name"; then
        echo "[INFO] $name is already running"
      else
        echo "[INFO] Starting $name..."
        nohup tart run --no-graphics "$name" > "/tmp/tart-$name.log" 2>&1 &
        echo "[INFO] $name started (PID $!)"
      fi
    BASH
  }
}

# ── Discover IPs via ARP ──────────────────────────────────────────────────────
# Deferred to apply time because it depends_on null_resource.boot.
# The external data source receives the MAC map via stdin JSON (query block)
# and returns a JSON map of {node_name_underscored: ip_address}.
data "external" "node_ips" {
  program = ["bash", "${path.module}/scripts/discover-ips.sh"]

  # Pass MACs keyed by node name (hyphens replaced with underscores because
  # the external provider requires valid JSON object keys that Terraform can
  # reference as attribute names).
  query = {
    for name, cfg in var.nodes :
    replace(name, "-", "_") => cfg.mac
  }

  depends_on = [null_resource.boot]
}
