# ==============================================================================
# Azure Service Plan
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/service_plan
# ==============================================================================

variable "service_plan_name" {
  description = "Service Plan name"
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

variable "os_type" {
  description = "OS type for the Service Plan (Linux or Windows)"
  type        = string
}

variable "sku_name" {
  description = "SKU name for the Service Plan (e.g., B1, B2, S1, P1v2)"
  type        = string
}

variable "worker_count" {
  description = "Number of workers for the Service Plan"
  type        = number
  default     = null
}

variable "maximum_elastic_worker_count" {
  description = "Maximum number of elastic workers for the Service Plan"
  type        = number
  default     = null
}

variable "per_site_scaling_enabled" {
  description = "Enable per-site scaling"
  type        = bool
  default     = false
}

variable "zone_balancing_enabled" {
  description = "Enable zone balancing"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
