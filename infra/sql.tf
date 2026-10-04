resource "azurerm_mssql_server" "sql" {
  name                         = "sql-namecounter-${var.environment}-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"

  tags = azurerm_resource_group.rg.tags
}

resource "azurerm_mssql_database" "db" {
  name                        = "NameCounterDB"
  server_id                   = azurerm_mssql_server.sql.id
  sku_name                    = "GP_S_Gen5_1"
  min_capacity                = 0.5
  auto_pause_delay_in_minutes = 60
  zone_redundant              = false

  tags = azurerm_resource_group.rg.tags
}

# Phase 1 only: lets Azure-hosted services reach the server (see Phase 2, section 6.5).
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "allow_student_ip" {
  name             = "AllowStudentWorkstation"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = var.client_ip_address
  end_ip_address   = var.client_ip_address
}