output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "database_name" {
  value = azurerm_mssql_database.db.name
}

output "function_app_name" {
  value = azurerm_linux_function_app.app.name
}

output "function_app_default_hostname" {
  value = azurerm_linux_function_app.app.default_hostname
}

output "app_insights_name" {
  value = azurerm_application_insights.appi.name
}