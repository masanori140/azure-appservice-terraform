# ==============================================================================
# Azure Service Plan
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/service_plan
# ==============================================================================

resource "azurerm_service_plan" "this" {
  name                         = var.service_plan_name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  os_type                      = var.os_type
  sku_name                     = var.sku_name
  worker_count                 = var.worker_count
  maximum_elastic_worker_count = var.maximum_elastic_worker_count
  per_site_scaling_enabled     = var.per_site_scaling_enabled
  zone_balancing_enabled       = var.zone_balancing_enabled
  tags                         = var.tags
}
