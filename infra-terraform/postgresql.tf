# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "postgres" {
  name                   = "psql-${var.environment}-${var.cluster_name}"
  resource_group_name    = azurerm_resource_group.aks.name
  location               = azurerm_resource_group.aks.location
  version                = var.postgresql_version
  administrator_login    = var.postgresql_admin_username
  administrator_password = var.postgresql_admin_password
  storage_mb             = var.postgresql_storage_mb
  sku_name               = var.postgresql_sku_name

  # Zone is set at creation time and cannot be changed
  lifecycle {
    ignore_changes = [zone]
  }
}

# PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "app_db" {
  name      = var.postgresql_database_name
  server_id = azurerm_postgresql_flexible_server.postgres.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Firewall rule to allow Azure services
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.postgres.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
