# Architecture

**Version:** 1.0
**Author:** Brandon Korous
**Last Updated:** 2026-10-29

How the shared infrastructure is split, who applies what, and why the order of
things matters.

## The line between this repository and the products

| This repository owns                                        | Each product repository owns                              |
| ----------------------------------------------------------- | --------------------------------------------------------- |
| The AKS cluster and its node pool                           | Its namespace's workloads (Deployments, Services, Jobs)   |
| The shared Postgres server and each product's database      | Its schema migrations and seed data                       |
| Each product's Key Vault, and the secrets Terraform generates | The secrets a person loads by hand (API keys, OAuth apps) |
| Storage accounts, Azure OpenAI and other managed services   | How its code uses them                                    |
| DNS records and the reserved ingress IP                     | Nothing about DNS                                         |
| The Caddy ingress and every product's route in the Caddyfile | Nothing about routing                                    |
| Each product's GitHub deploy identity and its role grants   | The workflow that uses that identity                      |

The test: **if it would still exist with the product's code deleted, it lives
here.** A database outlives a deploy; a vault outlives a rollout.

## Two identities, on purpose

| Identity                         | Applies                     | Can                                                                 |
| -------------------------------- | --------------------------- | ------------------------------------------------------------------- |
| `gha-wize-infrastructure-prod`   | `terraform/envs/azure`, `k8s/azure` | Contributor, the state account's data, AKS admin, Secrets Officer on the vaults it writes |
| `gha-sparx-prod-cus-bootstrap`   | `terraform/bootstrap-azure` | Create app registrations; grant only the roles in `local.bootstrap_roles` |

The first cannot grant roles, so the pipeline that changes the most often
cannot raise its own rights. The second trusts only this repository's
`bootstrap` GitHub Environment, limited to `main`.

Every product's deploy identity is the opposite shape: **Secrets User** on its
own vault (read, never write) and AKS access. The thing that deploys a product
can never rewrite a credential it is about to ship; only this repository's
release provisions.

## The release, in order

[.github/workflows/release.yml](../.github/workflows/release.yml), on every push
to `main`:

1. **infrastructure**: `terraform plan`, then a guard that stops the release on
   any plan that destroys or replaces a resource (a re-run by hand with
   `allow_infrastructure_destroy` lets it through), then `apply`.
2. **bootstrap**: the same for `terraform/bootstrap-azure`, under its own identity.
3. **cluster**:
   - `kubectl apply -k k8s/azure --prune` scoped to the label
     `app.kubernetes.io/managed-by: wize-infrastructure`, then waits for Caddy.
   - Reports the ingress IP.
   - Installs the WizeLens collector (Helm; its config comes from
     `kv-wizelens-prod-cus`).
   - Creates jotDOJO's owner role with `sql/jotdojo-bootstrap.sql`, as a Job in
     namespace `wize-infrastructure`, because the server is private and only a
     pod can reach it.

Infrastructure before cluster is the point: Caddy is pinned to an IP that the
Terraform reserves, and the jotDOJO Job reads a password the Terraform writes.

## Caddy lives in `sparx-prod`, and that is not a mistake

Caddy has run in sparx's namespace since sparx was the only product. Moving it
is a planned migration, not a side effect of this split:

- Its certificates live on `caddy-data`, a ReadWriteOnce disk. A PVC belongs to
  one namespace, so a new namespace starts empty and every tenant certificate is
  re-issued at once. Let's Encrypt allows 50 per registered domain per week; a
  large `sparx.zone` tenant base re-issuing together is a week of broken HTTPS.
- The reserved IP can be held by one Service at a time, so moving the Service
  means a gap where every hostname is dark.

So the objects stayed where they are and **ownership moved**. Three things
apply into `sparx-prod`, each with its own prune label, and none may ever share
a value:

| Label value             | Applied by                     | Owns                                  |
| ----------------------- | ------------------------------ | ------------------------------------- |
| `wize-infrastructure`   | this release, `k8s/azure`      | Caddy                                 |
| `sparx-release-infra`   | sparx's release, stage 1       | Typesense, PgBouncer, the media volume |
| `sparx-release-apps`    | sparx's release, stage 3       | Every sparx and Piggles workload       |

sparx's release has a step, "Hand the ingress over to wize-infrastructure",
that relabels any Caddy object still carrying `sparx-release-infra` before its
own prune runs. That is what makes it safe for either repository to release
first. `scripts/check-ingress.mjs` fails if this overlay ever emits a sparx
label.

The rendered Caddy objects are byte-identical to what sparx applied before the
split, apart from the label (the overlay keeps sparx's `serviceAccountName:
default` for that reason). A label change does not restart a pod, so the
handover causes no downtime. Keep it that way: any change to the pod template
or the Caddyfile restarts Caddy (it uses `Recreate`), and every hostname on the
cluster blips for 10 to 30 seconds.

## State

Both live roots keep their state in `stsparxprodcustfstate`
(`rg-sparx-prod-cus-tfstate`): `envs/azure.tfstate` and
`bootstrap-azure.tfstate`. Nothing was renamed in the move, so no state was
migrated. The names still say `sparx` because they were created when sparx was
the only product, and renaming a storage account means recreating it.

The state holds every generated password, including the Postgres admin. Only
the two identities above can read it. sparx's identity lost that access in the
split.

## What sparx still depends on here

- The cluster, namespace `sparx-prod`, and the Postgres server it migrates.
- `kv-sparx-prod-cus`, including `azure-storage-account` and
  `azure-storage-key`, which `terraform/envs/azure/main.tf` writes. sparx's
  release refuses to ship without them, because without them its media falls
  back to a local disk with no error.
- The Pub/Sub topic for every event in its catalog (`terraform/envs/prod`), kept
  honest by `scripts/check-event-topics.mjs`.
- The Cloudflare ranges in the Caddyfile, kept equal to sparx's
  `wizeworks/packages/client-ip` by `scripts/check-cloudflare-ranges.mjs`.

When a sparx change needs any of these to change, **this repository releases
first**. A sparx release that runs ahead fails loudly; it never half-deploys.
