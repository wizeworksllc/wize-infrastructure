# ---------------------------------------------------------------------------
# wize-infrastructure — the identity the INFRASTRUCTURE release runs as.
#
# Until 2026-10-29 this repository's contents lived inside sparx, and sparx's
# release applied them. That made every infrastructure change — a Caddy route
# for kanNINJA, a Key Vault for RocketEase, a DNS record for wize.works — wait
# behind a full sparx release: twenty images built, the sparx schema migrated,
# the sparx and Piggles containers rolled. About two hours, for a change that
# touched none of them. The reverse was just as wrong: a sparx release could
# fail on a Terraform plan for a product it does not ship.
#
# So the infrastructure has its own repository, its own release, and its own
# identity — this one. sparx's identity (`gha` in main.tf) is now an APPLICATION
# deployer like kanNINJA's or jotDOJO's: it reads its vault and rolls its own
# namespace, and it no longer holds the Terraform state or any other product's
# vault.
#
# WHAT THIS IDENTITY HOLDS, and why each:
#
#   Contributor (subscription)        envs/azure creates resource groups,
#                                     servers, vaults and the cluster.
#   Storage Blob Data Contributor     read and write Terraform state.
#     (tfstate account)
#   AKS Cluster User + RBAC Admin     the `kubernetes` provider (origin-ca.tf)
#     (subscription)                  and the ingress apply.
#   Key Vault Secrets Officer         envs/azure WRITES generated secrets:
#     (every product vault)           database passwords into each product's
#                                     vault, the media storage pair into sparx's.
#
# The per-product Secrets Officer grants live beside each product
# (`<product>_infra_kv` in agconn.tf, jotacular.tf, …) so deleting a product's
# file removes its grant with it. sparx's is below, because sparx's vault is
# created in main.tf rather than in a product file.
#
# ORG MOVE. The repository lives in the `wizeworksllc` organization from day
# one. The product repositories are moving there too; each one's subject prefix
# is a variable, so a transfer is a variable change applied by this release.
# docs/org-move.md has the order.
# ---------------------------------------------------------------------------

variable "infra_github_repository" {
  description = <<-EOT
    `owner/repo` of the infrastructure repository. Used in descriptions and in
    the setup commands; the federated SUBJECT comes from
    infra_github_subject_prefix below, because GitHub does not always build the
    subject from this string.
  EOT
  type        = string
  default     = "wizeworksllc/wize-infrastructure"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.infra_github_repository))
    error_message = "infra_github_repository must be in `owner/repo` form."
  }
}

variable "infra_github_subject_prefix" {
  description = <<-EOT
    The literal prefix of the OIDC `sub` claim GitHub mints for the
    infrastructure repository. Everything after it (`:ref:refs/heads/main`,
    `:environment:prod`) is appended below.

    READ IT, DO NOT GUESS IT. GitHub qualifies the subject with numeric owner and
    repository ids for SOME repositories (jotdojo gets
    `repo:brandonkorous@13042540/jotdojo@1341839746`, sparx gets the plain
    `repo:brandonkorous/sparx`), and nothing a repository setting does chooses
    which. After creating the repository:

      gh api repos/wizeworksllc/wize-infrastructure/actions/oidc/customization/sub

    and paste `sub_claim_prefix` here verbatim. A wrong value does not fail the
    apply; it fails the first release with AADSTS700213, naming the subject it
    RECEIVED, which is the value that belongs here.
  EOT
  type        = string
  # Read 2026-10-29 from the API above, right after the repository was created.
  default = "repo:wizeworksllc@350084568/wize-infrastructure@1439341797"

  validation {
    condition     = startswith(var.infra_github_subject_prefix, "repo:") && !endswith(var.infra_github_subject_prefix, ":")
    error_message = "infra_github_subject_prefix must start with `repo:` and must NOT end with a colon — paste sub_claim_prefix verbatim."
  }
}

resource "azuread_application" "infra" {
  display_name = "gha-wize-infrastructure-${var.environment}"
  owners       = local.app_owners
}

resource "azuread_service_principal" "infra" {
  client_id = azuread_application.infra.client_id
  owners    = local.app_owners
}

# The release's jobs run in the `prod` GitHub Environment, so this is the
# credential that applies.
resource "azuread_application_federated_identity_credential" "infra_environment" {
  application_id = azuread_application.infra.id
  display_name   = "gh-env-${var.environment}"
  description    = "The infrastructure release on ${var.infra_github_repository} (GitHub Environment `${var.environment}`)."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "${var.infra_github_subject_prefix}:environment:${var.environment}"
}

# Pushes to main outside an environment. Nothing applies from this context
# today; it exists so a job that only READS (a drift check, a plan) can log in
# without being bound to the environment that applies.
resource "azuread_application_federated_identity_credential" "infra_main" {
  application_id = azuread_application.infra.id
  display_name   = "gh-main"
  description    = "Pushes to main on ${var.infra_github_repository}."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "${var.infra_github_subject_prefix}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "infra_contributor" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.infra.object_id
}

resource "azurerm_role_assignment" "infra_blob" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.infra.object_id
}

resource "azurerm_role_assignment" "infra_aks_user" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azuread_service_principal.infra.object_id
}

resource "azurerm_role_assignment" "infra_aks_admin" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = azuread_service_principal.infra.object_id
}

# sparx's vault. envs/azure writes the media storage pair into it
# (`azure-storage-account`, `azure-storage-key`), which is how sparx's release
# learns them now that it no longer reads Terraform state.
resource "azurerm_role_assignment" "infra_sparx_kv" {
  scope                = azurerm_key_vault.app.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azuread_service_principal.infra.object_id
}

output "infra_client_id" {
  description = "Application (client) ID of the infrastructure release identity. Set as AZURE_CLIENT_ID on wize-infrastructure."
  value       = azuread_application.infra.client_id
}

output "infra_github_setup" {
  description = "One-time GitHub setup for wize-infrastructure: its identities, and the `prod` and `bootstrap` environments limited to main."
  value = join("\n", [
    "gh variable set AZURE_CLIENT_ID           -R ${var.infra_github_repository} -b '${azuread_application.infra.client_id}'",
    "gh variable set BOOTSTRAP_AZURE_CLIENT_ID -R ${var.infra_github_repository} -b '${azuread_application.bootstrap.client_id}'",
    "gh variable set AZURE_TENANT_ID           -R ${var.infra_github_repository} -b '${data.azurerm_client_config.current.tenant_id}'",
    "gh variable set AZURE_SUBSCRIPTION_ID     -R ${var.infra_github_repository} -b '${var.subscription_id}'",
    "gh api -X PUT repos/${var.infra_github_repository}/environments/${var.environment} -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'",
    "gh api -X POST repos/${var.infra_github_repository}/environments/${var.environment}/deployment-branch-policies -f name=main -f type=branch",
    "gh api -X PUT repos/${var.infra_github_repository}/environments/bootstrap -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'",
    "gh api -X POST repos/${var.infra_github_repository}/environments/bootstrap/deployment-branch-policies -f name=main -f type=branch",
  ])
}
