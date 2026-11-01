# Moving a repository into the `wizeworksllc` org

**Version:** 1.1
**Author:** Brandon Korous
**Last Updated:** 2026-10-30

wize-infrastructure was created in `wizeworksllc` from the start. On
2026-10-30 these repositories moved from the `brandonkorous` user to
`wizeworksllc`: sparx, kanninja, jotdojo, RocketEase, AgConnect, wizelens,
wizeworks and kanninja-marketplace. silicaui lives in its own org and did not
move. This is the checklist for the next repository that moves.

## What the 2026-10-30 move found

- **Every moved repository mints the id-qualified subject**,
  `repo:wizeworksllc@350084568/<repo>@<repo id>`, not the plain form. The repo
  id does not change in a transfer. `terraform/bootstrap-azure/org-move.tf`
  trusts both forms for every product, and it was released before the first
  transfer, so no login failed.
- **New org packages were private.** Fixed once, in the org settings: Packages,
  Package creation, Public. Since then a public repository's first push creates
  a public package. The settings form drops the setting on save while the
  Private box is disabled; that box must be enabled for the save to stick.
- **Release-only packages need a copy.** A product whose images or charts are
  built only by a tag release (wizelens) has nothing at the new path until its
  next tag. Every existing tag was copied with `crane copy` from a one-off
  workflow in that repository before the paths changed.
- **The Go module path did not change.** wizelens' module is still
  `github.com/brandonkorous/wizelens/go`. It resolves through GitHub's
  redirect, so no repository named `wizelens` may ever be created under
  `brandonkorous`.
- **Package API roots differ.** `/users/<owner>/packages` answers 404 for an
  org. sparx's image prune picks `/orgs/` or `/users/` from the owner's type.

## What breaks when a repository moves

1. **Azure login.** Each repository's deploy identity trusts an OIDC subject
   that starts with the repository's owner and name (`repo:<owner>/<repo>:...`).
   After the move GitHub mints `repo:wizeworksllc/sparx:...`, Entra matches the
   subject exactly, and every login fails with `AADSTS700213`. Nothing deploys
   until the subject is updated.
2. **Container image paths.** GHCR packages are owned by the account that
   pushed them. Images at `ghcr.io/<old owner>/...` do not move with the
   repository. The next build pushes to `ghcr.io/wizeworksllc/...`, and every
   manifest that names the old path keeps pulling the old image.
3. **Cross-repository checks.** This repository's CI checks sparx out from
   `vars.SPARX_REPOSITORY` (default `wizeworksllc/platform`, the repository that
   was named sparx until sparx docs/153 Phase 5). sparx's CI checks
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

4. **Image paths.** Update every `ghcr.io/<old owner>/` in the product's
   manifests and workflows to `ghcr.io/wizeworksllc/`. Run the product's
   release once so the images exist at the new path before anything pulls them.
   If the packages are private, the cluster's pull access must be granted on
   the new packages too.

5. **sparx only:** set `SPARX_REPOSITORY=wizeworksllc/platform` as a variable in
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
