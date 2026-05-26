# Partial backend config. The `key` (state file name) is supplied per-env at
# `terraform init` time by the pipeline, so the same code targets different
# state files per environment without any code change.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}
