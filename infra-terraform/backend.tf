terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstatedoraccount"
    container_name       = "tfstate"
    key                  = "application/learningsteps/terraform.tfstate"
  }
}