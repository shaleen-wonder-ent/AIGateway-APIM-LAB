locals {
  named_values_plain = {
    "entra-tenant-id"           = var.entra_tenant_id
    "aigw-client-app-id"        = var.aigw_client_app_id
    "aigw-caller-client-app-id" = var.aigw_caller_client_app_id
    "aigw-audience"             = var.aigw_audience
    "group-team-marketing"      = var.group_team_marketing
    "group-team-engineering"    = var.group_team_engineering
    "group-team-finance"        = var.group_team_finance
    "aws-region"                = var.aws_region
    "vertex-region"             = var.vertex_region
    "vertex-token-broker-url"   = var.vertex_token_broker_url
  }
}

resource "azurerm_api_management_named_value" "plain" {
  for_each            = local.named_values_plain
  name                = each.key
  display_name        = each.key
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  value               = each.value
}

resource "azurerm_api_management_named_value" "anthropic_key" {
  name                = "anthropic-api-key"
  display_name        = "anthropic-api-key"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  secret              = true
  value               = var.anthropic_api_key
}

resource "azurerm_api_management_named_value" "bedrock_token" {
  name                = "bedrock-bearer-token"
  display_name        = "bedrock-bearer-token"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  secret              = true
  value               = var.bedrock_bearer_token
}
