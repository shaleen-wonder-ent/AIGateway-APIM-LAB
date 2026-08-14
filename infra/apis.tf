resource "azurerm_api_management_api" "foundry" {
  name                  = "foundry"
  display_name          = "Microsoft Foundry (Azure OpenAI)"
  api_management_name   = azurerm_api_management.apim.name
  resource_group_name   = azurerm_resource_group.rg.name
  revision              = "1"
  path                  = "foundry"
  protocols             = ["https"]
  service_url           = "${azurerm_cognitive_account.foundry.endpoint}openai"
  subscription_required = true
}

resource "azurerm_api_management_api" "anthropic" {
  name                  = "anthropic"
  display_name          = "Anthropic"
  api_management_name   = azurerm_api_management.apim.name
  resource_group_name   = azurerm_resource_group.rg.name
  revision              = "1"
  path                  = "anthropic"
  protocols             = ["https"]
  service_url           = "https://api.anthropic.com"
  subscription_required = true
}

resource "azurerm_api_management_api" "bedrock" {
  name                  = "bedrock"
  display_name          = "AWS Bedrock"
  api_management_name   = azurerm_api_management.apim.name
  resource_group_name   = azurerm_resource_group.rg.name
  revision              = "1"
  path                  = "bedrock"
  protocols             = ["https"]
  service_url           = "https://bedrock-runtime.${var.aws_region}.amazonaws.com"
  subscription_required = true
}

resource "azurerm_api_management_api" "vertex" {
  name                  = "vertex"
  display_name          = "Google Vertex AI"
  api_management_name   = azurerm_api_management.apim.name
  resource_group_name   = azurerm_resource_group.rg.name
  revision              = "1"
  path                  = "vertex"
  protocols             = ["https"]
  service_url           = "https://${var.vertex_region}-aiplatform.googleapis.com"
  subscription_required = true
}
