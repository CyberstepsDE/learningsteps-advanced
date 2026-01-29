resource "azurerm_resource_group" "aks" {
  name       = "rg-${var.environment}-aks"
  location   = var.location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  # Security: Enable RBAC (AVD-AZU-0042)
  role_based_access_control_enabled = true

  # Security: Restrict API server access (AVD-AZU-0041)
  api_server_access_profile {
    authorized_ip_ranges = var.authorized_ip_ranges
  }

  # Security: Enable network policy (AVD-AZU-0043)
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.vm_size

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

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
  zone                   = "1"
}

# Firewall rule to allow Azure services
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.postgres.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
