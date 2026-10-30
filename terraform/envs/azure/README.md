# Azure environment

**Version:** 2.0
**Author:** Brandon Korous
**Last Updated:** 2026-10-29

The cost-constrained deployment that replaces GKE + Cloud SQL. Budget is $1000 of
credit targeted to last ~10 months, and every sizing decision here is made
against that number — the reasoning sits next to each resource in
[main.tf](main.tf) rather than in a separate doc.

This Terraform creates **infrastructure only**: resource group, VNet, AKS, and
Postgres. Workloads come from a kustomize overlay on top (see _Next_ below).

## Cost

| Component                     | Choice                                   | ~$/mo         |
| ----------------------------- | ---------------------------------------- | ------------- |
| AKS control plane             | `Free` tier — no SLA                     | $0            |
| Node                          | 1 × `Standard_D2_v3`, ephemeral OS disk  | $70           |
| Postgres                      | Flexible Server B1ms + 32 GiB, PG 18     | $16           |
| Egress load balancer          | AKS-provisioned, unavoidable — see below | $4–20         |
| PVCs                          | Typesense + media                        | ~$6           |
| Registry / Redis / ingress LB | GHCR / dropped / cloudflared             | $0            |
| **Total**                     |                                          | **≈ $96–112** |

Two things that could move it:

- **The egress load balancer is the one number I am not confident about.** AKS
  provisions a Standard LB for outbound SNAT even with no `LoadBalancer` Service.
  The cluster genuinely needs egress — GHCR pulls, Postgres, and cloudflared
  dialling out — so it cannot be removed. It is somewhere between the public IP
  alone (~$4) and a full Standard LB (~$18–20). **Check the first week's actual
  bill.** `managedNATGateway` was considered and rejected at ~$32/mo.
- **New Azure accounts get 12 months free** of Flexible Server B1ms + 32 GiB. If
  this subscription is inside its first year, Postgres is $0.

## Why these SKUs

**`Standard_D2_v3` because it is not burstable.** A B-series node throttles to
baseline once burst credits are exhausted, and the moment that bites is a mass
cold start — 20 containers booting after a rollout. api-rest is known to lose
that fight: it crashlooped for ~30h on GKE (~400 restarts, exit 137) purely from
CPU starvation during boot, which is what the 300s `startupProbe` in
sparx's [k8s/apps/api-rest.yaml](https://github.com/brandonkorous/sparx/blob/main/k8s/apps/api-rest.yaml) exists to survive.
`Standard_D2ads_v5` was the first choice but returns
`NotAvailableForSubscription` in eastus2/eastus/centralus here.

**`Free` AKS tier** saves the ~$74/mo that the GKE Autopilot equivalent charged.
That single difference is most of why this environment is affordable.

**Postgres is VNet-private**, mirroring the private-IP Cloud SQL it replaces. So
you cannot reach it from a laptop — migrations run as an in-cluster Job, exactly
as sparx's [wizeworks/packages/db/CLAUDE.md](https://github.com/brandonkorous/sparx/blob/main/wizeworks/packages/db/CLAUDE.md) already describes.

## Apply

This repository's release applies it (`.github/workflows/release.yml`, the
`infrastructure` job) on every push to `main`: plan, refuse a plan that destroys
anything unless `allow_infrastructure_destroy` was ticked on a manual run, then
apply. Nothing else applies it. A read-only plan from a laptop is fine:

```bash
cd terraform/envs/azure
terraform init
terraform plan -lock=false
```

## Required manual step: create the `sparx_app` role

**The apps cannot connect until this is done.** Terraform creates the
`sparx_owner` admin login, but `sparx_app` — the unprivileged, `NOBYPASSRLS` role
every application connection uses — comes from
sparx's [wizeworks/packages/db/docker/init/01-roles.sql](https://github.com/brandonkorous/sparx/blob/main/wizeworks/packages/db/docker/init/01-roles.sql).
That file is a **Docker image entrypoint convention**, not a Postgres feature, so
a managed server will never run it.

It also cannot be run from a laptop, because the server is VNet-private. Run it
from inside the cluster:

```bash
kubectl run psql --rm -it --restart=Never --image=postgres:18-alpine -- \
  psql "postgresql://sparx_owner:<password>@<fqdn>:5432/sparx?sslmode=require"
```

Paste the contents of `01-roles.sql`, adjusting the passwords — the file's
hardcoded `devpassword` is correct for a Docker-network-isolated dev database and
wrong for anything else. Whatever you choose must match `DATABASE_URL` in the k8s
Secret.

Get the values from Terraform:

```bash
terraform output -raw postgres_admin_password
terraform output -raw postgres_fqdn
```

## State

Remote, in `stsparxprodcustfstate` (`rg-sparx-prod-cus-tfstate`), key
`envs/azure.tfstate`, reached with Entra identity (`use_azuread_auth`), never an
account key. The account and its container are created by `../../bootstrap-azure`.

**The state holds the Postgres admin password and every product's generated
secrets in plaintext.** Only this repository's release identity and the
bootstrap identity can read it. A `terraform.tfstate` or `.backup` left on a
laptop from the local-backend days is a live credential: delete it.
