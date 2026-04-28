output "node_ips" {
  description = "Map of VM name (with hyphens, e.g. talos-cp1) to discovered IP address."
  value = {
    for name in keys(var.nodes) :
    name => data.external.node_ips.result[replace(name, "-", "_")]
  }
}

output "vm_ids" {
  description = "Map of VM name to null_resource ID. Use as a depends_on signal."
  value       = { for k, v in null_resource.vm : k => v.id }
}
