# ==============================================================================
# Azure Linux Web App
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_web_app
# ==============================================================================

output "linux_web_app" {
  description = "Linux Web App object"
  value       = azurerm_linux_web_app.this
  sensitive   = true
}
