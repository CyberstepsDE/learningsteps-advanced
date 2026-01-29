output "cluster_id" {
  value       = azurerm_kubernetes_cluster.aks.id
  description = "AKS cluster ID"
}

output "cluster_name" {
  value       = azurerm_kubernetes_cluster.aks.name
  description = "AKS cluster name"
}

output "resource_group_name" {
  value       = azurerm_resource_group.aks.name
  description = "Resource group name"
}

output "acr_login_server" {
  value       = azurerm_container_registry.acr.login_server
  description = "ACR login server URL"
}

output "acr_id" {
  value       = azurerm_container_registry.acr.id
  description = "ACR resource ID"
}

output "postgresql_server_name" {
  value       = azurerm_postgresql_flexible_server.postgres.name
  description = "PostgreSQL server name"
}

output "postgresql_fqdn" {
  value       = azurerm_postgresql_flexible_server.postgres.fqdn
  description = "PostgreSQL server FQDN"
}

output "postgresql_database_name" {
  value       = azurerm_postgresql_flexible_server_database.app_db.name
  description = "PostgreSQL database name"
}
