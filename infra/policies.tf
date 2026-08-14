locals {
  fragment_ids = [
    azurerm_api_management_policy_fragment.auth_entra.id,
    azurerm_api_management_policy_fragment.content_safety.id,
    azurerm_api_management_policy_fragment.audit_log.id,
  ]

  named_value_ids = concat(
    [for nv in azurerm_api_management_named_value.plain : nv.id],
    [azurerm_api_management_named_value.anthropic_key.id,
    azurerm_api_management_named_value.bedrock_token.id],
  )
}

resource "azurerm_api_management_policy" "global" {
  api_management_id = azurerm_api_management.apim.id
  xml_content       = file("${path.module}/../policies/global.xml")

  depends_on = [
    azurerm_api_management_policy_fragment.audit_log,
    azurerm_api_management_named_value.plain,
  ]
}

resource "azurerm_api_management_api_policy" "foundry" {
  api_name            = azurerm_api_management_api.foundry.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  xml_content         = file("${path.module}/../policies/api-foundry.xml")

  depends_on = [
    azurerm_api_management_backend.foundry,
    azurerm_api_management_backend.embeddings,
    azurerm_api_management_policy_fragment.content_safety,
  ]
}

resource "azurerm_api_management_api_policy" "anthropic" {
  api_name            = azurerm_api_management_api.anthropic.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  xml_content         = file("${path.module}/../policies/api-anthropic.xml")

  depends_on = [
    azurerm_api_management_named_value.anthropic_key,
    azurerm_api_management_policy_fragment.content_safety,
  ]
}

resource "azurerm_api_management_api_policy" "bedrock" {
  api_name            = azurerm_api_management_api.bedrock.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  xml_content         = file("${path.module}/../policies/api-bedrock.xml")

  depends_on = [
    azurerm_api_management_named_value.bedrock_token,
    azurerm_api_management_policy_fragment.content_safety,
  ]
}

resource "azurerm_api_management_api_policy" "vertex" {
  api_name            = azurerm_api_management_api.vertex.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  xml_content         = file("${path.module}/../policies/api-vertex.xml")

  depends_on = [
    azurerm_api_management_policy_fragment.content_safety,
  ]
}
