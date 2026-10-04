terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod"
    storage_account_name = "tfstatergyr" # <-- your state storage account
    container_name       = "tfstate"
    key                  = "namecounter.prod.tfstate"
    use_azuread_auth     = true # authenticate with your az login identity
  }
}

provider "azurerm" {
  resource_provider_registrations = "core"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}