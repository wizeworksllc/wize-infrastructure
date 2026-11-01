# ---------------------------------------------------------------------------
# Piggles — the Key Vault for meetpiggles.com, getpiggles.com and mypiggles.com.
#
# Piggles moves out of the sparx repository into wizeworksllc/piggles (sparx
# docs/153, Phase 4). In sparx its pods read `sparx-app-secrets`, the store that
# holds every platform credential. Since Phase 1 no Piggles app touches the
# database or runs an auth server: each one calls api-rest over HTTP. So the few
# values a Piggles pod still needs get their own vault, and the Piggles pipeline
# can read nothing of sparx's.
#
# Its own vault rather than a secret in sparx's: a vault is the smallest scope
# Key Vault RBAC can grant, and a shared vault would let this pipeline read every
# sparx credential.
#
# ORDER, because the two halves live in different states: this file is applied
# by this repository's `infrastructure` job, and bootstrap-azure/piggles.tf (the
# `bootstrap` job, which runs after it) looks the vault up and grants roles on it.
#
# NO DATABASE. Piggles' rows live in the platform database, which api-rest owns.
# ---------------------------------------------------------------------------

variable "piggles_enabled" {
  description = <<-EOT
    Master switch for the Piggles Key Vault. Independent of the switch of the
    same name in terraform/bootstrap-azure, which governs the CI identity.
    Standard tier has no base fee; operations are $0.03 per 10,000.
  EOT
  type        = bool
  default     = true
}

variable "piggles_key_vault_name" {
  description = "Globally unique (a DNS label), 3-24 characters. Keep in step with the variable of the same name in terraform/bootstrap-azure."
  type        = string
  default     = "kv-piggles-prod-cus"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.piggles_key_vault_name))
    error_message = "Key Vault names are 3-24 chars, start with a letter, end alphanumeric, and allow only letters, digits and hyphens."
  }
}

resource "azurerm_key_vault" "piggles" {
  count               = var.piggles_enabled ? 1 : 0
  name                = var.piggles_key_vault_name
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

output "piggles_key_vault_name" {
  description = "Vault holding the Piggles apps' secrets. Set as AZURE_KEY_VAULT_NAME on the piggles repo."
  value       = var.piggles_enabled ? azurerm_key_vault.piggles[0].name : null
}
