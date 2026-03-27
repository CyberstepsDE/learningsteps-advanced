terraform {
  backend "azurerm" {
    resource_group_name  = "demo-cybersteps-01"
    storage_account_name = "terraformstatebucket12"
    container_name       = "tfstate"
    key                  = "application/learningsteps/terraform.tfstate"
  }
}