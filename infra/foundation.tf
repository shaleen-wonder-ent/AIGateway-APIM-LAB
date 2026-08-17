locals {
  foundry_account_name        = "aoai-${var.apim_name}"
  content_safety_account_name = "cs-${var.apim_name}"
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
    version = "2024-11-20"
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

