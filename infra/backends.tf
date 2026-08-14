resource "azurerm_api_management_backend" "foundry" {
  name                = "foundry-backend"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  protocol            = "http"
  url                 = "${azurerm_cognitive_account.foundry.endpoint}openai"
}

resource "azurerm_api_management_backend" "embeddings" {
  name                = "embeddings-backend"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  protocol            = "http"
  url                 = "${azurerm_cognitive_account.foundry.endpoint}openai"
}

resource "azurerm_api_management_backend" "content_safety" {
  name                = "contentsafety-backend"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  protocol            = "http"
  url                 = azurerm_cognitive_account.content_safety.endpoint
}
