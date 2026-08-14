locals {
  foundry_account_name        = "aoai-${var.apim_name}"
  content_safety_account_name = "cs-${var.apim_name}"
  key_vault_name              = "kv-${substr(replace(var.apim_name, "-", ""), 0, 18)}"
}

# ------------------------------------------------------------
# Azure OpenAI / Microsoft Foundry
# ------------------------------------------------------------
resource "azurerm_cognitive_account" "foundry" {
  name                  = local.foundry_account_name
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = local.foundry_account_name
  local_auth_enabled    = false
}

resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-08-06"
  }

  sku {
    name     = "GlobalStandard"
    capacity = 50
  }
}

resource "azurerm_cognitive_deployment" "embeddings" {
  name                 = "text-embedding-ada-002"
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  model {
    format  = "OpenAI"
    name    = "text-embedding-ada-002"
    version = "2"
  }

  sku {
    name     = "Standard"
    capacity = 30
  }
}

# ------------------------------------------------------------
# Azure AI Content Safety
# ------------------------------------------------------------
resource "azurerm_cognitive_account" "content_safety" {
  name                  = local.content_safety_account_name
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  kind                  = "ContentSafety"
  sku_name              = "S0"
  custom_subdomain_name = local.content_safety_account_name
  local_auth_enabled    = false
}

# ------------------------------------------------------------
# Key Vault for vendor secrets (Anthropic key, Bedrock token)
# ------------------------------------------------------------
resource "azurerm_key_vault" "kv" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

# Terraform runner needs write access to seed the secrets below.
resource "azurerm_role_assignment" "tf_kv_admin" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "anthropic_api_key" {
  name         = "anthropic-api-key"
  value        = var.anthropic_api_key
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.tf_kv_admin]
}

resource "azurerm_key_vault_secret" "bedrock_bearer_token" {
  name         = "bedrock-bearer-token"
  value        = var.bedrock_bearer_token
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.tf_kv_admin]
}
