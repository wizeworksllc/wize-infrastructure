# ---------------------------------------------------------------------------
# sparx's apps — the CI identity for wizeworksllc/sparx.
#
# sparx's three apps (web, workbench, market) are a co-tenant on this cluster
# like Piggles: their own namespace (`sparx`), their own repository, their own
# pipeline and their own Key Vault. They left the platform repository
# (wizeworksllc/platform, which was named sparx) in sparx docs/153, Phase 5.
#
# NOT the platform's `gha` identity. That one deploys every platform service and
# reads every platform credential; this one reaches only the cluster and its own
# vault, so the apps' pipeline can read nothing of the platform's.
#
# The vault is created in terraform/envs/azure/sparx-apps.tf, applied by the
# `infrastructure` job. This file only LOOKS IT UP and grants roles on it.
#
# NOTE ON `data.azurerm_client_config.current`: declared once for this root
# module, in jotacular.tf. Do not re-declare it here.
# ---------------------------------------------------------------------------

variable "sparx_apps_enabled" {
  description = <<-EOT
    Master switch for the sparx apps' pipeline identity. It gates nothing billable:
    an app registration, a service principal and federated credentials are
    free. Setting it false and applying takes the identity away.
  EOT
  type        = bool
  default     = true
}

variable "sparx_apps_github_branches" {
  description = <<-EOT
    Branches whose workflow runs may assume this identity. One credential is
    minted per branch, because Entra matches the subject exactly. Just `main`:
    sparx's apps deploy on push to main and nothing else does.
  EOT
  type        = set(string)
  default     = ["main"]
}

variable "sparx_apps_github_subject_prefix" {
  description = <<-EOT
    The literal prefix of the OIDC `sub` claim GitHub mints for this repository.
    The credentials below append `:ref:refs/heads/main` and `:environment:prod`.

    THE QUALIFIED FORM, WITH NUMERIC IDS. The repository was created on
    2026-11-01 with immutable subjects on, so GitHub qualifies the owner and the
    repository with their ids. Read back, not assembled:

        gh api repos/wizeworksllc/sparx/actions/oidc/customization/sub \
          --jq .sub_claim_prefix

    Re-run that first if deploys fail with AADSTS700213 ("No matching
    federated identity record found for presented assertion subject").
  EOT
  type        = string
  default     = "repo:wizeworksllc@350084568/sparx@1442332718"

  validation {
    condition     = startswith(var.sparx_apps_github_subject_prefix, "repo:")
    error_message = "sparx_apps_github_subject_prefix must start with `repo:`. Paste sub_claim_prefix verbatim, without a trailing colon."
  }

  validation {
    condition     = !endswith(var.sparx_apps_github_subject_prefix, ":")
    error_message = "sparx_apps_github_subject_prefix must NOT end with a colon. The credentials append `:ref:...` and `:environment:...` themselves."
  }
}

locals {
  sparx_apps_count = var.sparx_apps_enabled ? 1 : 0
  sparx_apps_repo  = "wizeworksllc/sparx"
}

variable "sparx_apps_key_vault_name" {
  description = <<-EOT
    The vault terraform/envs/azure/sparx-apps.tf creates. NAMED here rather than
    referenced, because the two live in different Terraform states. Keep in step
    with the variable of the same name over there.
  EOT
  type        = string
  default     = "kv-sparxapps-prod-cus"
}

data "azurerm_key_vault" "sparx_apps" {
  count               = local.sparx_apps_count
  name                = var.sparx_apps_key_vault_name
  resource_group_name = "rg-${var.workload}-${var.environment}-${local.loc}"
}

# ---------------------------------------------------------------------------
# Identity. Its own app registration: a federated credential's subject names
# the repository, so only this repository's workflows can assume it.
# ---------------------------------------------------------------------------
resource "azuread_application" "sparx_apps_gha" {
  count        = local.sparx_apps_count
  display_name = "gha-sparx-apps-prod"
  owners       = local.app_owners
}

resource "azuread_service_principal" "sparx_apps_gha" {
  count     = local.sparx_apps_count
  client_id = azuread_application.sparx_apps_gha[0].client_id
  owners    = local.app_owners
}

resource "azuread_application_federated_identity_credential" "sparx_apps_branch" {
  for_each = var.sparx_apps_enabled ? var.sparx_apps_github_branches : toset([])

  application_id = azuread_application.sparx_apps_gha[0].id
  display_name   = "github-${each.value}"
  description    = "Pushes to ${each.value} in ${local.sparx_apps_repo}."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "${var.sparx_apps_github_subject_prefix}:ref:refs/heads/${each.value}"
}

# Minted before any job declares `environment: prod`, so adding a deployment
# gate later does not fail with AADSTS700213.
resource "azuread_application_federated_identity_credential" "sparx_apps_environment" {
  count          = local.sparx_apps_count
  application_id = azuread_application.sparx_apps_gha[0].id
  display_name   = "github-environment-prod"
  description    = "Jobs bound to the `prod` GitHub Environment in ${local.sparx_apps_repo}."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "${var.sparx_apps_github_subject_prefix}:environment:prod"
}

# ---------------------------------------------------------------------------
# Permissions: the cluster and its own vault for the pipeline, and write on the
# vault for the human who loads it. Subscription scope for the cluster role,
# matching every other tenant (see wizeworks.tf for why, and for the caveat that
# Cluster User is admin-equivalent while AKS local accounts stay enabled).
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "sparx_apps_gha_aks" {
  count                = local.sparx_apps_count
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azuread_service_principal.sparx_apps_gha[0].object_id
}

# Read its OWN vault. Get and list, never write.
resource "azurerm_role_assignment" "sparx_apps_gha_kv" {
  count                = local.sparx_apps_count
  scope                = data.azurerm_key_vault.sparx_apps[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.sparx_apps_gha[0].object_id
}

resource "azurerm_role_assignment" "sparx_apps_operator_kv" {
  count                = local.sparx_apps_count
  scope                = data.azurerm_key_vault.sparx_apps[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.operator_object_id
}

# NO AcrPull: images come from GHCR (ghcr.io/wizeworksllc/sparx-*).

output "sparx_apps_client_id" {
  description = "Application (client) ID of gha-sparx-apps-prod. Set as AZURE_CLIENT_ID on the sparx repo."
  value       = var.sparx_apps_enabled ? azuread_application.sparx_apps_gha[0].client_id : null
}

output "sparx_apps_github_setup" {
  description = "Repository VARIABLES (public identifiers, not secrets) to set on the sparx repo so its pipeline can authenticate and read its vault."
  value = var.sparx_apps_enabled ? [
    "gh variable set AZURE_CLIENT_ID       -R ${local.sparx_apps_repo} -b '${azuread_application.sparx_apps_gha[0].client_id}'",
    "gh variable set AZURE_TENANT_ID       -R ${local.sparx_apps_repo} -b '${data.azurerm_client_config.current.tenant_id}'",
    "gh variable set AZURE_SUBSCRIPTION_ID -R ${local.sparx_apps_repo} -b '${var.subscription_id}'",
    "gh variable set AZURE_KEY_VAULT_NAME  -R ${local.sparx_apps_repo} -b '${var.sparx_apps_key_vault_name}'",
  ] : []
}
