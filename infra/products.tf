locals {
  products = {
    marketing = {
      display_name = "Team - Marketing"
      policy_file  = "product-team-marketing.xml"
    }
    engineering = {
      display_name = "Team - Engineering"
      policy_file  = "product-team-engineering.xml"
    }
    finance = {
      display_name = "Team - Finance"
      policy_file  = "product-team-finance.xml"
    }
  }

  product_apis = {
    for pair in setproduct(keys(local.products), ["foundry", "anthropic", "bedrock", "vertex"]) :
    "${pair[0]}-${pair[1]}" => { product = pair[0], api = pair[1] }
  }
}

resource "azurerm_api_management_product" "team" {
  for_each              = local.products
  product_id            = "team-${each.key}"
  display_name          = each.value.display_name
  api_management_name   = azurerm_api_management.apim.name
  resource_group_name   = azurerm_resource_group.rg.name
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_subscription" "team" {
  for_each = azurerm_api_management_product.team

  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  product_id          = each.value.id
  display_name        = "${each.value.display_name} Subscription"
  state               = "active"
  subscription_id     = "team-${each.key}"
}

resource "azurerm_api_management_product_api" "attach" {
  for_each            = local.product_apis
  api_name            = each.value.api
  product_id          = azurerm_api_management_product.team[each.value.product].product_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name

  depends_on = [
    azurerm_api_management_api.foundry,
    azurerm_api_management_api.anthropic,
    azurerm_api_management_api.bedrock,
    azurerm_api_management_api.vertex,
  ]
}

resource "azurerm_api_management_product_policy" "team" {
  for_each            = local.products
  product_id          = azurerm_api_management_product.team[each.key].product_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  xml_content         = file("${path.module}/../policies/${each.value.policy_file}")
}
