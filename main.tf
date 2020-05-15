provider "azurerm" {
    version = "=2.10.0"
    features {}
}

resource "random_string" "unique" {
    length  = 6
    special = false
    upper   = false
}

resource "azurerm_resource_group" "rg" {
    name     = "rg-${random_string.unique.result}"
    location = "westeurope"
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
    name                = "kv-${random_string.unique.result}"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    tenant_id           = data.azurerm_client_config.current.tenant_id
    sku_name            = "standard"

    network_acls {
        default_action = "Allow"
        bypass         = "AzureServices"
    }
}

# Set permissions for currently logged-in Terraform SP to be able to manage secrets
resource "azurerm_key_vault_access_policy" "kv" {
    key_vault_id       = azurerm_key_vault.kv.id
    tenant_id          = data.azurerm_client_config.current.tenant_id
    object_id          = data.azurerm_client_config.current.object_id
    secret_permissions = [
        "Get",
        "Set",
        "Delete"
    ]
}

resource "azurerm_key_vault_secret" "demo" {
    name         = "demo-secret"
    value        = "demo-value"
    key_vault_id = azurerm_key_vault.kv.id

    # Must wait for Terraform SP policy to kick in before creating secrets
    depends_on   = [azurerm_key_vault_access_policy.kv]
}

resource "azurerm_app_service_plan" "app" {
    name                = "plan-${random_string.unique.result}"
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location

    sku {
        tier = "Free"
        size = "F1"
    }
}

locals {
    kv_format = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.kv.vault_uri}secrets/%s/)"
}

resource "azurerm_app_service" "app" {
    name                = "app-${random_string.unique.result}"
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location
    app_service_plan_id = azurerm_app_service_plan.app.id

    identity {
        type = "SystemAssigned"
    }

    app_settings = {
        "demo" = format(local.kv_format, azurerm_key_vault_secret.demo.name)
    }
}

resource "azurerm_key_vault_access_policy" "app" {
    key_vault_id       = azurerm_key_vault.kv.id
    tenant_id          = azurerm_app_service.app.identity.0.tenant_id
    object_id          = azurerm_app_service.app.identity.0.principal_id
    secret_permissions = ["Get"]
}
