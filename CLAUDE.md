# CLAUDE.md

Guidance for Claude Code in wize-infrastructure: the shared infrastructure every
WizeWorks product runs on. Read [README.md](README.md) for the map and
[docs/architecture.md](docs/architecture.md) for the why.

## What this repository is

Terraform for the Azure cluster, the shared Postgres server, every product's
vault, storage and database, DNS, and the GitHub deploy identities; plus the
Caddy ingress and its routing table. It moved out of the sparx repository on
2026-10-29 so a route or a vault no longer waits on a two-hour sparx release.

It serves sparx, Piggles, kanNINJA, jotDOJO, RocketEase, AgConnect, WizeLens,
silicaui and wize.works. **A change here can take every one of them down.** Act
like it.

## Rules

- **Never apply by hand.** The release applies Terraform and `k8s/azure`. A
  read-only `terraform plan -lock=false` from a laptop is fine. No
  `terraform apply`, no `kubectl apply/delete/label/patch` against the cluster.
  Reads (`get`, `describe`, `logs`) are fine. The two documented exceptions are
  in `terraform/bootstrap-azure/README.md` ("When a person must apply"), and a
  person does those, not an agent.
- **No drift.** Anything changed outside Terraform must be mirrored into it in
  the same session.
- **Never raise ongoing cost without asking.** A new managed service, a bigger
  SKU, more replicas or nodes: say the monthly cost and ask Brandon first.
- **Destroys stop the release.** The plan guard blocks any delete or replace.
  Do not tell anyone to tick `allow_infrastructure_destroy` unless you have
  read the plan and the loss is intended.
- **Caddy restarts on any Caddyfile or pod-template change** (`Recreate`, every
  hostname on the cluster dark for 10 to 30 seconds). Batch route changes.
  Do not touch the Caddyfile or `k8s/ingress/deployment.yaml` for a comment
  alone. (One known stale comment: the Caddyfile says client-ip's test checks
  the Cloudflare ranges; `scripts/check-cloudflare-ranges.mjs` does now. Fix it
  with the next real Caddyfile change.)
- **Caddy stays in namespace `sparx-prod`** until a planned migration moves it
  with its certificates. Its prune label is `wize-infrastructure` and must
  never equal `sparx-release-infra` or `sparx-release-apps`
  (`scripts/check-ingress.mjs` enforces it).
- **Renames are migrations.** State keys, storage account names and resource
  names still say `sparx` because they predate the split. Renaming one
  recreates the resource. Don't.
- **Read the OIDC subject from GitHub, never guess it:**
  `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`.
- **Repository creation, visibility changes, transfers, and anything else that
  publishes something** are Brandon's to run. Give him the exact command.
- Never `git commit`, `git push`, `git stash`, or `git checkout -- <file>`.
  Leave changes in the tree and report them.
- Docs: `Version`, `Author: Brandon Korous`, `Last Updated` (ISO date) header;
  bump on a material edit. No em-dashes in new prose. American spelling.

## Before you push

```bash
terraform fmt -check -recursive terraform
node --test scripts/*.test.mjs
node scripts/check-ingress.mjs
bash .github/scripts/caddy-smoke.sh            # needs Docker or CADDY_BIN
node scripts/check-event-topics.mjs --sparx ../sparx.works
node scripts/check-cloudflare-ranges.mjs --sparx ../sparx.works
```

`terraform validate` needs `terraform init -backend=false` per root
(`.github/scripts/tf-validate.sh` does all four).

## Working with sparx

- sparx's release no longer runs Terraform. Its stage 1 syncs `sparx-app-secrets`
  from `kv-sparx-prod-cus` and applies its own `k8s/azure/infra`.
- sparx reads `azure-storage-account` / `azure-storage-key` from its vault;
  `terraform/envs/azure/main.tf` (`media_storage`) writes them. Removing them
  fails sparx's release on purpose.
- A new sparx event needs its topic in `terraform/envs/prod/main.tf` here.
  sparx's `pnpm check:events` finds this checkout beside it and fails until the
  topic exists.
- When a sparx change needs infrastructure, this repository **releases first**.

## Common tasks

- New route: `k8s/ingress/Caddyfile`, then `caddy-smoke.sh`.
- New product: [docs/adding-a-product.md](docs/adding-a-product.md).
- Moving a repo into the `wizeworksllc` org: [docs/org-move.md](docs/org-move.md).
