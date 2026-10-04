resource "azurerm_storage_account" "func_sa" {
  name                     = "stfunc${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = azurerm_resource_group.rg.tags
}

resource "azurerm_service_plan" "asp" {
  name                = "asp-namecounter-${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption (serverless)

  tags = azurerm_resource_group.rg.tags
}

resource "azurerm_linux_function_app" "app" {
  name                = "func-namecounter-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.asp.id

  storage_account_name       = azurerm_storage_account.func_sa.name
  storage_account_access_key = azurerm_storage_account.func_sa.primary_access_key

  https_only = true

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "ENABLE_ORYX_BUILD"              = "true"
    "SQL_CONNECTION_STRING" = join("", [
      "Driver={ODBC Driver 18 for SQL Server};",
      "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;",
      "Database=${azurerm_mssql_database.db.name};",
      "Uid=${var.sql_admin_login};Pwd=${var.sql_admin_password};",
      "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    ])
  }

  tags = azurerm_resource_group.rg.tags
}