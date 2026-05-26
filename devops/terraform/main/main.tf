# Placeholder workload. Real modules go here. The point of this file is to
# show that the SAME code runs against every environment — differences come
# from var-files, not branching logic.

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = var.env_name
  }
}
