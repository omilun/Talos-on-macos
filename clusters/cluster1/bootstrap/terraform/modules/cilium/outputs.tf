output "install_id" {
  description = "null_resource ID for the Cilium installation. Use as a depends_on handle."
  value       = null_resource.cilium.id
}
