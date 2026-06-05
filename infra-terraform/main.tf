resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.environment}-aks"
  location = var.location
}
