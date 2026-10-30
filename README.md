# wize-infrastructure

**Version:** 1.0
**Author:** Brandon Korous
**Last Updated:** 2026-10-29

The shared infrastructure every WizeWorks product runs on: the Azure Kubernetes
cluster, the shared Postgres server, each product's Key Vault, storage and
database, DNS, the GitHub deploy identities, and the Caddy ingress that routes
every product's hostnames.

Products on it today: sparx and Piggles (one repository), kanNINJA, jotDOJO,
RocketEase, AgConnect, WizeLens, silicaui and wize.works.

## Why it is its own repository

Until 2026-10-29 all of this lived inside the sparx repository and rode the
sparx release. That release builds about twenty images and migrates the sparx
database, so one new Caddy route for kanNINJA waited about two hours. It also
meant sparx's deploy identity could read every product's database password.

Now a route, a vault or a DNS record is a change here, and this release ships
it in minutes. It builds no images and touches no product's data.

## What is where

| Path                        | What it is                                                                  |
| --------------------------- | --------------------------------------------------------------------------- |
| `terraform/envs/azure`      | The live environment: cluster, Postgres, vaults, storage, DNS, the ingress IP |
| `terraform/bootstrap-azure` | Identities, the state account, role grants the release itself may not make |
| `terraform/envs/prod`, `terraform/bootstrap` | The retired GCP environment, kept as code and `validate`-clean |
| `terraform/modules/*`       | Modules (`dns` is used by `envs/azure`)                                     |
| `k8s/ingress`               | Caddy, the ONE routing table (`Caddyfile`), its Service, PVC and probes     |
| `k8s/azure`                 | The ingress overlay for AKS: reserved IP, storage class, ownership label    |
| `sql/jotdojo-bootstrap.sql` | jotDOJO's owner role on the shared Postgres server                          |
| `scripts/`                  | Structural checks (see below)                                              |
| `.github/workflows`         | `release.yml` (ships it) and `ci.yml` (checks it)                           |

## How it ships

Every push to `main` runs [.github/workflows/release.yml](.github/workflows/release.yml):

1. **infrastructure** applies `terraform/envs/azure`. A plan that destroys
   anything stops the release unless a person re-runs it by hand with
   `allow_infrastructure_destroy` ticked.
2. **bootstrap** applies `terraform/bootstrap-azure` under its own identity.
3. **cluster** applies `k8s/azure` (Caddy), waits for it, reports the ingress
   IP, installs the WizeLens collector, and creates jotDOJO's owner role.

Detail: [docs/architecture.md](docs/architecture.md).

## Checks

[ci.yml](.github/workflows/ci.yml) runs on every pull request and every day:

- `terraform fmt -check` and `validate` for all four roots.
- `scripts/check-ingress.mjs`: Caddy keeps `Recreate` and its pods share a node
  (its certificate disk is ReadWriteOnce), and nothing still carries a sparx
  ownership label.
- `.github/scripts/caddy-smoke.sh`: Caddy accepts the Caddyfile.
- Two checks across repositories, against sparx's `main`:
  - `scripts/check-event-topics.mjs`: every event in sparx's catalog has a
    Pub/Sub topic in `terraform/envs/prod`.
  - `scripts/check-cloudflare-ranges.mjs`: Caddy and sparx's
    `wizeworks/packages/client-ip` trust the same Cloudflare ranges.

sparx's CI runs the same two checks against its own pull requests, so the
change that breaks one is the one that fails.

Run them locally:

```bash
node --test scripts/*.test.mjs
node scripts/check-ingress.mjs
node scripts/check-event-topics.mjs --sparx ../sparx.works
node scripts/check-cloudflare-ranges.mjs --sparx ../sparx.works
```

## Common jobs

- **Add a route for a product**: edit `k8s/ingress/Caddyfile`, merge, done.
- **Add a product**: [docs/adding-a-product.md](docs/adding-a-product.md).
- **Add an event to sparx**: add its topic in `terraform/envs/prod/main.tf`
  here, release this first, then merge the sparx change.
- **Move a repository into the `wizeworksllc` org**: [docs/org-move.md](docs/org-move.md).

Agent instructions: [CLAUDE.md](CLAUDE.md).
