# ==============================================================================
# Azure Linux Web App
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_web_app
# ==============================================================================

resource "azurerm_linux_web_app" "this" {
  name                          = var.web_app_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = var.service_plan_id
  https_only                    = var.https_only
  public_network_access_enabled = var.public_network_access_enabled
  app_settings                  = var.app_settings
  tags                          = var.tags

  site_config {
    always_on           = var.site_config.always_on
    ftps_state          = var.site_config.ftps_state
    http2_enabled       = var.site_config.http2_enabled
    minimum_tls_version = var.site_config.minimum_tls_version

    dynamic "application_stack" {
      for_each = var.site_config.application_stack
      content {
        docker_image_name        = application_stack.value.docker_image_name
        docker_registry_url      = application_stack.value.docker_registry_url
        docker_registry_username = application_stack.value.docker_registry_username
        docker_registry_password = application_stack.value.docker_registry_password
        dotnet_version           = application_stack.value.dotnet_version
        go_version               = application_stack.value.go_version
        java_server              = application_stack.value.java_server
        java_server_version      = application_stack.value.java_server_version
        java_version             = application_stack.value.java_version
        node_version             = application_stack.value.node_version
        php_version              = application_stack.value.php_version
        python_version           = application_stack.value.python_version
        ruby_version             = application_stack.value.ruby_version
      }
    }
  }
}
