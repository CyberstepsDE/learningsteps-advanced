resource "azurerm_resource_group" "aks" {
  name     = "rg-${var.environment}-aks"
  location = var.location
}
