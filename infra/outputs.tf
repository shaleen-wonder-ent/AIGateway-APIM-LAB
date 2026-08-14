output "apim_gateway_url" {
  value = azurerm_api_management.apim.gateway_url
}

output "apim_principal_id" {
  value = azurerm_api_management.apim.identity[0].principal_id
}

output "app_insights_id" {
  value = azurerm_application_insights.ai.id
}

output "product_ids" {
  value = { for k, p in azurerm_api_management_product.team : k => p.product_id }
}
