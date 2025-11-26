# ==============================================================================
# Version Constraints
# ==============================================================================

terraform_version_constraint  = "~> 1.13.0"
terragrunt_version_constraint = "~> 0.91.0"

# ==============================================================================
# Locals
# ==============================================================================

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Authentication credentials from environment variables (.env)
  subscription_id = get_env("ARM_SUBSCRIPTION_ID")
  tenant_id       = get_env("ARM_TENANT_ID")

  # Infrastructure configuration from env.hcl
  resource_group_name  = local.environment_vars.locals.resource_group_name
  storage_account_name = local.environment_vars.locals.storage_account_name
  location             = local.environment_vars.locals.location
  env                  = local.environment_vars.locals.env
  service              = local.environment_vars.locals.service
}

# ==============================================================================
# Provider Generation
# ==============================================================================

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_providers {
        azurerm = {
          source  = "hashicorp/azurerm"
          version = "~> 4.0"
        }
      }
    }

    provider "azurerm" {
      features {
        key_vault {
          purge_soft_delete_on_destroy    = false
          recover_soft_deleted_key_vaults = true
        }
      }
      storage_use_azuread = true
    }
  EOF
}

# ==============================================================================
# Remote State Configuration
# ==============================================================================

remote_state {
  backend = "azurerm"

  config = {
    resource_group_name  = local.resource_group_name
    storage_account_name = local.storage_account_name
    container_name       = "tfstate"
    key                  = "tfstate/${local.env}/${basename(get_terragrunt_dir())}.tfstate"
    subscription_id      = local.subscription_id
    use_azuread_auth     = true
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# ==============================================================================
# Common Inputs
# ==============================================================================

inputs = {
  tenant_id = local.tenant_id

  location = {
    id = local.location
  }

  tags = {
    environment = local.env
    service     = local.service
    managed_by  = "terraform"
  }
}
