# Moving a repository into the `wizeworksllc` org

**Version:** 1.0
**Author:** Brandon Korous
**Last Updated:** 2026-10-29

wize-infrastructure was created in `wizeworksllc` from the start. The product
repositories (sparx, kanNINJA, jotDOJO, RocketEase, AgConnect, WizeLens,
wizeworks, silicaui) still live under `brandonkorous` and move one at a time.
This is the checklist for one move.

## What breaks when a repository moves

1. **Azure login.** Each repository's deploy identity trusts an OIDC subject
   that starts with the repository's name (`repo:brandonkorous/sparx:...`).
   After the move GitHub mints `repo:wizeworksllc/sparx:...`, Entra matches the
   subject exactly, and every login fails with `AADSTS700213`. Nothing deploys
   until the subject is updated.
2. **Container image paths.** GHCR packages are owned by the account that
   pushed them. Images at `ghcr.io/brandonkorous/...` do not move with the
   repository. The next build pushes to `ghcr.io/wizeworksllc/...`, and every
   manifest that names the old path keeps pulling the old image.
3. **Cross-repository checks.** This repository's CI checks sparx out from
   `vars.SPARX_REPOSITORY` (default `brandonkorous/sparx`). sparx's CI checks
   this repository out from `vars.INFRA_REPOSITORY` (default
   `wizeworksllc/wize-infrastructure`).
4. **Remote kustomize bases.** sparx's `k8s/local/kustomization.yaml` names
   `github.com/wizeworksllc/wize-infrastructure` (already correct).

GitHub redirects the old URL for clones, pushes and the web UI, so local
checkouts keep working. The redirect does NOT help items 1 and 2.

## Steps, for one repository

1. **Before the move, add the new subject alongside the old one** so there is
   no gap. In `terraform/bootstrap-azure`, the product's
   `<product>_github_repository` and `<product>_github_subject_prefix`
   variables (for sparx: `github_subject_prefix`, plus `github_owner` and
   `github_repository`, in `variables.tf`) drive its federated credentials. The cleanest path is a
   second set of federated credentials for the new subject, released here
   first, then the old set removed after the move.

   If you accept a few minutes where that product cannot deploy, just change
   the variable defaults after the move instead (step 3).

2. **Transfer the repository** in GitHub (Settings, Danger zone, Transfer).
   Repository variables, secrets and environments move with it.

3. **Read the new subject prefix** and set it here:

   ```bash
   gh api repos/wizeworksllc/<repo>/actions/oidc/customization/sub
   ```

   An org can make the prefix id-qualified (`repo:wizeworksllc@<id>/<repo>@<id>`).
   Use exactly what that command implies. Merge, and let this release apply it.

4. **Image paths.** Update every `ghcr.io/brandonkorous/` in the product's
   manifests and workflows to `ghcr.io/wizeworksllc/`. Run the product's
   release once so the images exist at the new path before anything pulls them.
   If the packages are private, the cluster's pull access must be granted on
   the new packages too.

5. **sparx only:** set `SPARX_REPOSITORY=wizeworksllc/sparx` as a variable in
   this repository, so its CI checks the right sparx out (the redirect would
   cover it, but an explicit name does not depend on it).

6. **Update the docs that name the old owner.** At least:
   `terraform/envs/azure/README.md` (links into sparx),
   `terraform/bootstrap-azure/README.md`, this file's list above, and the
   product's own CLAUDE.md and README.

7. **Delete the old federated credentials** if you added a second set in step 1.

## Order for the whole move

sparx last. It has the most images, the most cross-repository checks and the
longest release, so the other repositories are cheaper places to find a
mistake in this checklist.
