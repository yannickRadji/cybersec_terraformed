resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-namecounter-${var.environment}-${random_string.suffix.result}"
  location = var.location

  tags = {
    Project     = "Cybersecurity-Lab"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}