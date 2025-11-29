# ==============================================================================
# Azure Service Plan
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/service_plan
# ==============================================================================

output "service_plan" {
  description = "Service Plan object"
  value       = azurerm_service_plan.this
}
