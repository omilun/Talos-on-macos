# ── Flux v2 bootstrap ─────────────────────────────────────────────────────────
# Installs Flux v2 controllers into the cluster (flux-system namespace).
#
# If flux_git_repository_url is provided, also bootstraps Flux with a
# GitRepository source and Kustomization pointing at flux_git_path. This
# enables fully declarative GitOps: all platform resources can be managed via
# Git commits rather than Terraform re-applies.
#
# If flux_git_repository_url is empty, only the Flux controllers are installed.
# You can configure the Git source later with: flux create source git ...

resource "null_resource" "flux" {
  triggers = {
    version    = var.flux_version
    git_url    = var.flux_git_repository_url
    git_branch = var.flux_git_branch
    git_path   = var.flux_git_path
    kubeconfig = var.kubeconfig_path
    script_md5 = filemd5("${path.module}/scripts/install-flux.sh")
  }

  provisioner "local-exec" {
    command     = "bash '${path.module}/scripts/install-flux.sh'"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG              = var.kubeconfig_path
      FLUX_VERSION            = var.flux_version
      FLUX_GIT_REPOSITORY_URL = var.flux_git_repository_url
      FLUX_GIT_BRANCH         = var.flux_git_branch
      FLUX_GIT_PATH           = var.flux_git_path
      GITHUB_TOKEN            = var.flux_github_token
    }
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "flux uninstall --silent --kubeconfig '${self.triggers.kubeconfig}' 2>/dev/null || true"
    interpreter = ["/bin/bash", "-c"]
  }
}
