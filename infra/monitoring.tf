resource "azurerm_log_analytics_workspace" "law" {
  name                = "log-namecounter-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = azurerm_resource_group.rg.tags
}

resource "azurerm_application_insights" "appi" {
  name                = "appi-namecounter-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  workspace_id        = azurerm_log_analytics_workspace.law.id # workspace-based Application Insights
  application_type    = "web"

  tags = azurerm_resource_group.rg.tags
}