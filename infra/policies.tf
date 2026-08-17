locals {
  private_ip_filter_policy = <<-XML
        <ip-filter action="allow">
            <address-range from="10.0.0.0" to="10.255.255.255" />
            <address-range from="172.16.0.0" to="172.31.255.255" />
            <address-range from="192.168.0.0" to="192.168.255.255" />
        </ip-filter>
  XML

  global_policy_xml = replace(
    file("${path.module}/../policies/global.xml"),
    "<!-- {{private-ip-filter}} -->",
    var.enable_private_ip_filter ? local.private_ip_filter_policy : ""
  )
}

resource "azurerm_api_management_policy" "global" {
  api_management_id = azurerm_api_management.apim.id
  xml_content       = local.global_policy_xml

  depends_on = [
    azurerm_api_management_logger.appi,
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
