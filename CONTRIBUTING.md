# Contributing

Thank you for your interest in contributing! This is a personal homelab / learning project, but PRs and issues are welcome.

---

## Ways to Contribute

- **Bug reports** — open an issue with your macOS version, Tart version, Talos version, and the error output
- **Documentation improvements** — typos, unclear steps, missing gotchas
- **New features** — new Terraform modules, new GitOps components, new Flux configurations
- **Tested on non-Apple-Silicon** — Intel Mac / Linux reports welcome (untested)

---

## Development Setup

1. Fork the repo and clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/Talos-on-macos.git
   cd Talos-on-macos
   ```

2. Create a branch:
   ```bash
   git checkout -b feat/my-feature
   ```

3. Test your changes by running a full `tofu apply` against a real cluster.

4. Commit with a conventional commit message:
   ```
   feat(monitoring): add Tempo distributed tracing
   fix(loki): mount emptyDir for read-only root filesystem
   docs(readme): add NVRAM seed instructions
   chore(deps): bump cilium to v1.20
   ```

5. Open a pull request against `main`.

---

## Project Structure

See [README.md](README.md) for the full directory structure and architecture explanation.

- **Terraform changes** → `bootstrap/terraform/`
- **Platform/chart changes** → `gitops/infrastructure/`
- **Application changes** → `gitops/apps/`
- **Talos config changes** → `patches/`

---

## Guidelines

- **Keep secrets out of the repo** — use `.gitignore`, never commit `terraform.tfvars`, `*.tfstate`, or `_out/`
- **Test idempotency** — `tofu apply` run twice should produce no changes
- **Document gotchas** — if you hit a non-obvious issue, add it to the Troubleshooting section in the README
- **Small PRs** — one feature or fix per PR makes review faster

---

## Commit Signing

Not required, but appreciated. Configure Git signing with:
```bash
git config commit.gpgsign true
```

---

## License

By contributing, you agree your contributions will be licensed under [MIT](LICENSE).
