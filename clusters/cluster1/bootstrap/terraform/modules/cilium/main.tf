resource "null_resource" "cilium" {
  triggers = {
    kubeconfig = var.kubeconfig_path
    version    = var.cilium_version
    script_md5 = filemd5("${path.module}/scripts/install-cilium.sh")
  }

  provisioner "local-exec" {
    command     = "bash ${path.module}/scripts/install-cilium.sh"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG     = var.kubeconfig_path
      CILIUM_VERSION = var.cilium_version
    }
  }
}
