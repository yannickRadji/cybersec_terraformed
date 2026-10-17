data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                       = "kv-nc-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false # lab only; enable in production
  soft_delete_retention_days = 7

  tags = azurerm_resource_group.rg.tags
}

# You (the deployer) need to write the secret.
resource "azurerm_role_assignment" "me_kv_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# The Function App only needs to read secrets.
resource "azurerm_role_assignment" "func_kv_reader" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.app.identity[0].principal_id
}

resource "azurerm_key_vault_secret" "sql_conn" {
  name         = "SqlConnString"
  key_vault_id = azurerm_key_vault.kv.id
  value = join("", [
    "Driver={ODBC Driver 18 for SQL Server};",
    "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;",
    "Database=${azurerm_mssql_database.db.name};",
    "Uid=${var.sql_admin_login};Pwd=${var.sql_admin_password};",
    "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
  ])

  depends_on = [azurerm_role_assignment.me_kv_officer] # role propagation is invisible to Terraform
}