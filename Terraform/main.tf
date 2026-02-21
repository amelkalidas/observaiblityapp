terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

data "azurerm_client_config" "current" {}

# 1. Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# 2. Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "law" {
  name                = var.log_analytics_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# 3. Data Collection Endpoint (DCE) - Explicit
resource "azurerm_monitor_data_collection_endpoint" "dce" {
  name                          = "dce-aks-${var.location}"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  kind                          = "Linux"
  public_network_access_enabled = true # Replaces "network_access_type"
  tags                          = var.tags
}

# 4. Data Collection Rule (DCR) - Explicit
resource "azurerm_monitor_data_collection_rule" "dcr" {
  name                        = "dcr-aks-container-insights"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id
  tags                        = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = "law-destination"
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerLogV2", "Microsoft-KubeEvents"]
    destinations = ["law-destination"]
    # COST SAVING: Drop any logs that are 'Debug' level
    transform_kql = "source | where LogLevel != 'Debug'"
  }

  data_sources {
    extension {
      streams        = ["Microsoft-ContainerLogV2", "Microsoft-KubeEvents"]
      extension_name = "ContainerInsights"
      extension_json = jsonencode({
        "dataCollectionSettings": {
          "interval": "1m",
          "namespaceFilteringMode": "Include",
          # Example: Only collect logs from these namespaces
          "namespaces": ["default", "kube-system", "production"] 
        }
      })
      name = "ContainerInsightsExtension"
    }
  }
}

# 5. AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-prod"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  # Enable Monitoring Addon with Managed Identity
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.law.id
    msi_auth_for_monitoring_enabled = true # REQUIRED for DCRs
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  tags = var.tags
}

# 6. Associate DCR to AKS (The Link)
resource "azurerm_monitor_data_collection_rule_association" "dcra" {
  name                    = "dcra-aks-link"
  target_resource_id      = azurerm_kubernetes_cluster.aks.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr.id
  description             = "Link AKS to DCR for Container Insights"
}

# --- Grafana Authentication Section ---

# 7. Azure AD Application for Grafana
data "azuread_client_config" "current" {}

resource "azuread_application" "grafana_app" {
  display_name = var.grafana_app_name
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "grafana_sp" {
  client_id = azuread_application.grafana_app.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal_password" "grafana_secret" {
  service_principal_id = azuread_service_principal.grafana_sp.id
}

# 8. Role Assignment: Grant "Monitoring Reader" to Grafana SP on the Resource Group
# This allows Grafana to query logs via "Resource-Context"
resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azuread_service_principal.grafana_sp.object_id
}

# --- Outputs ---

output "grafana_tenant_id" {
  value = data.azuread_client_config.current.tenant_id
  description = "Grafana: Tenant ID"
}

output "grafana_client_id" {
  value = azuread_application.grafana_app.client_id
  description = "Grafana: Client ID"
}

output "grafana_client_secret" {
  value     = azuread_service_principal_password.grafana_secret.value
  sensitive = true
  description = "Grafana: Client Secret"
}

output "default_subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
  description = "Grafana: Default Subscription ID"
}
