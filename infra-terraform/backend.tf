terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstateblob234"
    container_name       = "tfstate"
    key                  = "application/learningsteps/terraform.tfstate"
  }
}
