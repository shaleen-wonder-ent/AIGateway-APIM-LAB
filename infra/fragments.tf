resource "azurerm_api_management_policy_fragment" "content_safety" {
  name              = "fragment-content-safety"
  api_management_id = azurerm_api_management.apim.id
  format            = "xml"
  value             = file("${path.module}/../policies/fragment-content-safety.xml")

  depends_on = [azurerm_api_management_backend.content_safety]
}
