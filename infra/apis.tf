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

locals {
  api_operations = {
    foundry = {
      api_name     = azurerm_api_management_api.foundry.name
      display_name = "Create chat completion"
      url_template = "/openai/deployments/{deployment}/chat/completions"
      parameters   = ["deployment"]
    }
    anthropic = {
      api_name     = azurerm_api_management_api.anthropic.name
      display_name = "Create message"
      url_template = "/v1/messages"
      parameters   = []
    }
    bedrock = {
      api_name     = azurerm_api_management_api.bedrock.name
      display_name = "Invoke model"
      url_template = "/model/{modelId}/invoke"
      parameters   = ["modelId"]
    }
    vertex = {
      api_name     = azurerm_api_management_api.vertex.name
      display_name = "Generate content"
      url_template = "/v1/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent"
      parameters   = ["project", "location", "model"]
    }
  }
}

resource "azurerm_api_management_api_operation" "proxy" {
  for_each = local.api_operations

  operation_id        = "proxy-all"
  api_name            = each.value.api_name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  display_name        = each.value.display_name
  method              = "POST"
  url_template        = each.value.url_template

  dynamic "template_parameter" {
    for_each = each.value.parameters

    content {
      name     = template_parameter.value
      required = true
      type     = "string"
    }
  }
}
