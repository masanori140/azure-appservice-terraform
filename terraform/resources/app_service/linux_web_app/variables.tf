# ==============================================================================
# Azure Linux Web App
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_web_app
# ==============================================================================

variable "web_app_name" {
  description = "Linux Web App name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "service_plan_id" {
  description = "Service Plan ID"
  type        = string
}

variable "https_only" {
  description = "Force HTTPS only"
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Enable public network access"
  type        = bool
  default     = true
}

variable "app_settings" {
  description = "Application settings"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "site_config" {
  description = "Site configuration"
  type = object({
    always_on           = optional(bool, true)
    ftps_state          = optional(string, "Disabled")
    http2_enabled       = optional(bool, true)
    minimum_tls_version = optional(string, "1.2")
    application_stack = optional(list(object({
      docker_image_name        = optional(string)
      docker_registry_url      = optional(string)
      docker_registry_username = optional(string)
      docker_registry_password = optional(string)
      dotnet_version           = optional(string)
      go_version               = optional(string)
      java_server              = optional(string)
      java_server_version      = optional(string)
      java_version             = optional(string)
      node_version             = optional(string)
      php_version              = optional(string)
      python_version           = optional(string)
      ruby_version             = optional(string)
    })), [])
  })
  default = {}
}
