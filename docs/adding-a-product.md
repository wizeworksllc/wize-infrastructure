# Adding a product

**Version:** 1.0
**Author:** Brandon Korous
**Last Updated:** 2026-10-29

How a new product gets onto the shared cluster. kanNINJA is the cleanest
example to copy: `terraform/envs/azure/kanninja.tf` and
`terraform/bootstrap-azure/kanninja.tf`.

## 1. Decide: shared Postgres server, or its own

- **Its own server** (kanNINJA, RocketEase): the product creates its own roles
  from its own pipeline, and nothing here has to know its schema. Costs about
  $13 a month more. Prefer it.
- **A database on the shared server** (jotDOJO): cheaper, but the server admin
  is `sparx_owner`, so this repository has to mint the product's owner role for
  it (`sql/jotdojo-bootstrap.sql` and the Job in `release.yml`).

## 2. The environment file: `terraform/envs/azure/<product>.tf`

One file per product, so deleting the product is deleting the file. It holds:

- A `<product>_enabled` switch.
- The database (or server), the Key Vault, storage, and anything else managed.
- The secrets Terraform can generate, written into the product's vault.
- The Secrets Officer grant for `azuread_service_principal.infra` is NOT here;
  it is in the bootstrap file, because only the bootstrap identity can grant.

## 3. The identity file: `terraform/bootstrap-azure/<product>.tf`

- An app registration for the product's GitHub Actions, with federated
  credentials for its branches and its deploy environment.
- `<product>_github_subject_prefix`: read it from GitHub, never guess it:
  `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`.
- Grants: **Key Vault Secrets User** on its own vault (read only), AKS cluster
  user, and **Key Vault Secrets Officer** for `azuread_service_principal.infra`
  so this release can write the generated secrets.
- Any new role must also be in `local.bootstrap_roles` in `ci.tf`, or the
  bootstrap apply fails with a 403.
- An output `<product>_github_setup` with the `gh variable set` commands.

## 4. The route: `k8s/ingress/Caddyfile`

Add the product's host blocks. Use `import tls_policy` for its hostnames so
on-demand TLS can issue for them, and point `reverse_proxy` at the product's
Service by its full in-cluster name (`<svc>.<namespace>.svc.cluster.local`).
Run `bash .github/scripts/caddy-smoke.sh` before you push.

A Caddyfile change restarts Caddy (about 10 to 30 seconds for every hostname),
so batch route changes rather than shipping them one at a time.

## 5. DNS

Records live in `terraform/modules/dns` (used by `envs/azure`). Point the
product's hostnames at the ingress IP (`terraform output ingress_ip`).

## 6. Order

1. Merge here. The release creates the vault, database and identity, and Caddy
   starts routing (to a Service that does not exist yet; that returns 502,
   which is expected).
2. Run the `gh variable set` commands from the new output in the product's
   repository.
3. Load the hand-managed secrets into its vault.
4. The product's own pipeline deploys its workloads.
