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
