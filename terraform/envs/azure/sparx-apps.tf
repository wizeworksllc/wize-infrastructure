# ---------------------------------------------------------------------------
# sparx's apps — the Key Vault for sparx.works, app.sparx.works and sparx.market.
#
# sparx's three apps (web, workbench, market) move out of the platform
# repository (wizeworksllc/platform, which was named sparx) into a new
# wizeworksllc/sparx (sparx docs/153, Phase 5), and deploy into namespace
# `sparx`. In the platform they read `sparx-app-secrets`, the store that holds
# every platform credential. Since Phase 1 no sparx app touches the database or
# runs an auth server: each one calls api-rest over HTTP. So the few values an
# app pod still needs (its Server Actions key and its WizeLens key) get their own
# vault, and the sparx apps' pipeline can read nothing of the platform's.
#
# Its own vault rather than a secret in the platform's: a vault is the smallest
# scope Key Vault RBAC can grant. The same shape as Piggles (piggles.tf).
#
# ORDER, because the two halves live in different states: this file is applied
# by this repository's `infrastructure` job, and bootstrap-azure/sparx-apps.tf
# (the `bootstrap` job, which runs after it) looks the vault up and grants roles.
#
# NO DATABASE. sparx's rows live in the platform database, which api-rest owns.
# ---------------------------------------------------------------------------

variable "sparx_apps_enabled" {
  description = <<-EOT
    Master switch for the sparx apps' Key Vault. Independent of the switch of the
    same name in terraform/bootstrap-azure, which governs the CI identity.
    Standard tier has no base fee; operations are $0.03 per 10,000.
  EOT
  type        = bool
  default     = true
}

variable "sparx_apps_key_vault_name" {
  description = "Globally unique (a DNS label), 3-24 characters. Keep in step with the variable of the same name in terraform/bootstrap-azure."
  type        = string
  default     = "kv-sparxapps-prod-cus"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.sparx_apps_key_vault_name))
    error_message = "Key Vault names are 3-24 chars, start with a letter, end alphanumeric, and allow only letters, digits and hyphens."
  }
}

resource "azurerm_key_vault" "sparx_apps" {
  count               = var.sparx_apps_enabled ? 1 : 0
  name                = var.sparx_apps_key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = local.tags

  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  lifecycle {
    prevent_destroy = true
  }
}

output "sparx_apps_key_vault_name" {
  description = "Vault holding the sparx apps' secrets. Set as AZURE_KEY_VAULT_NAME on the sparx repo."
  value       = var.sparx_apps_enabled ? azurerm_key_vault.sparx_apps[0].name : null
}
