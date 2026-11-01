# ---------------------------------------------------------------------------
# Piggles — the CI identity for wizeworksllc/piggles.
#
# Piggles is a co-tenant on this cluster like wize.works and kanNINJA: its own
# namespace (`piggles`), its own repository, its own pipeline, and its own Key
# Vault. It left the sparx repository in sparx docs/153, Phase 4.
#
# The vault is created in terraform/envs/azure/piggles.tf, applied by the
# `infrastructure` job. This file only LOOKS IT UP and grants roles on it; the
# `bootstrap` job runs after `infrastructure`, so the vault exists by then.
#
# WHAT IS NOT HERE: the workloads. The Deployments, Services and the namespace
# are Kustomize YAML in the piggles repo under `k8s/`. The Caddy routes for its
# three hostnames are in k8s/ingress/Caddyfile.
#
# NOTE ON `data.azurerm_client_config.current`: declared once for this root
# module, in jotacular.tf. Do not re-declare it here.
# ---------------------------------------------------------------------------

variable "piggles_enabled" {
  description = <<-EOT
    Master switch for the Piggles pipeline identity. It gates nothing billable:
    an app registration, a service principal and federated credentials are
    free. Setting it false and applying takes the identity away.
  EOT
  type        = bool
  default     = true
}

variable "piggles_github_branches" {
  description = <<-EOT
    Branches whose workflow runs may assume this identity. One credential is
    minted per branch, because Entra matches the subject exactly. Just `main`:
    Piggles deploys on push to main and nothing else does.
  EOT
  type        = set(string)
  default     = ["main"]
}

variable "piggles_github_subject_prefix" {
  description = <<-EOT
    The literal prefix of the OIDC `sub` claim GitHub mints for this repository.
    The credentials below append `:ref:refs/heads/main` and `:environment:prod`.

    THE QUALIFIED FORM, WITH NUMERIC IDS. The repository was created on
    2026-10-31 with immutable subjects on, so GitHub qualifies the owner and the
    repository with their ids. Read back, not assembled:

        gh api repos/wizeworksllc/piggles/actions/oidc/customization/sub \
          --jq .sub_claim_prefix

    Re-run that first if deploys fail with AADSTS700213 ("No matching
    federated identity record found for presented assertion subject").
  EOT
  type        = string
  default     = "repo:wizeworksllc@350084568/piggles@1441498904"

  validation {
    condition     = startswith(var.piggles_github_subject_prefix, "repo:")
    error_message = "piggles_github_subject_prefix must start with `repo:`. Paste sub_claim_prefix verbatim, without a trailing colon."
  }

  validation {
    condition     = !endswith(var.piggles_github_subject_prefix, ":")
    error_message = "piggles_github_subject_prefix must NOT end with a colon. The credentials append `:ref:...` and `:environment:...` themselves."
  }
}

locals {
  piggles_count = var.piggles_enabled ? 1 : 0
  piggles_repo  = "wizeworksllc/piggles"
}

variable "piggles_key_vault_name" {
  description = <<-EOT
    The vault terraform/envs/azure/piggles.tf creates. NAMED here rather than
    referenced, because the two live in different Terraform states. Keep in step
    with the variable of the same name over there.
  EOT
  type        = string
  default     = "kv-piggles-prod-cus"
}

data "azurerm_key_vault" "piggles" {
  count               = local.piggles_count
  name                = var.piggles_key_vault_name
  resource_group_name = "rg-${var.workload}-${var.environment}-${local.loc}"
}

# ---------------------------------------------------------------------------
# Identity. Its own app registration: a federated credential's subject names
# the repository, so only this repository's workflows can assume it.
# ---------------------------------------------------------------------------
resource "azuread_application" "piggles_gha" {
  count        = local.piggles_count
  display_name = "gha-piggles-prod"
  owners       = local.app_owners
}

resource "azuread_service_principal" "piggles_gha" {
  count     = local.piggles_count
  client_id = azuread_application.piggles_gha[0].client_id
  owners    = local.app_owners
}

resource "azuread_application_federated_identity_credential" "piggles_branch" {
  for_each = var.piggles_enabled ? var.piggles_github_branches : toset([])

  application_id = azuread_application.piggles_gha[0].id
  display_name   = "github-${each.value}"
  description    = "Pushes to ${each.value} in ${local.piggles_repo}."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "${var.piggles_github_subject_prefix}:ref:refs/heads/${each.value}"
}

# Minted before any job declares `environment: prod`, so adding a deployment
# gate later does not fail with AADSTS700213.
resource "azuread_application_federated_identity_credential" "piggles_environment" {
  count          = local.piggles_count
  application_id = azuread_application.piggles_gha[0].id
  display_name   = "github-environment-prod"
  description    = "Jobs bound to the `prod` GitHub Environment in ${local.piggles_repo}."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "${var.piggles_github_subject_prefix}:environment:prod"
}

# ---------------------------------------------------------------------------
# Permissions: the cluster and its own vault for the pipeline, and write on the
# vault for the human who loads it. Subscription scope for the cluster role,
# matching every other tenant (see wizeworks.tf for why, and for the caveat that
# Cluster User is admin-equivalent while AKS local accounts stay enabled).
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "piggles_gha_aks" {
  count                = local.piggles_count
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azuread_service_principal.piggles_gha[0].object_id
}

# Read its OWN vault. Get and list, never write.
resource "azurerm_role_assignment" "piggles_gha_kv" {
  count                = local.piggles_count
  scope                = data.azurerm_key_vault.piggles[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.piggles_gha[0].object_id
}

resource "azurerm_role_assignment" "piggles_operator_kv" {
  count                = local.piggles_count
  scope                = data.azurerm_key_vault.piggles[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.operator_object_id
}

# NO AcrPull: images come from GHCR (ghcr.io/wizeworksllc/piggles-*).

output "piggles_client_id" {
  description = "Application (client) ID of gha-piggles-prod. Set as AZURE_CLIENT_ID on the piggles repo."
  value       = var.piggles_enabled ? azuread_application.piggles_gha[0].client_id : null
}

output "piggles_github_setup" {
  description = "Repository VARIABLES (public identifiers, not secrets) to set on the piggles repo so its pipeline can authenticate and read its vault."
  value = var.piggles_enabled ? [
    "gh variable set AZURE_CLIENT_ID       -R ${local.piggles_repo} -b '${azuread_application.piggles_gha[0].client_id}'",
    "gh variable set AZURE_TENANT_ID       -R ${local.piggles_repo} -b '${data.azurerm_client_config.current.tenant_id}'",
    "gh variable set AZURE_SUBSCRIPTION_ID -R ${local.piggles_repo} -b '${var.subscription_id}'",
    "gh variable set AZURE_KEY_VAULT_NAME  -R ${local.piggles_repo} -b '${var.piggles_key_vault_name}'",
  ] : []
}
