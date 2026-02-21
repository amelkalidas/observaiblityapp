terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

data "azurerm_client_config" "current" {}

# ============================================================
# 1. Resource Group
# ============================================================
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ============================================================
# 2. Log Analytics Workspace
# ============================================================
resource "azurerm_log_analytics_workspace" "law" {
  name                = var.log_analytics_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# ============================================================
# 3. AKS Cluster
# ============================================================
# Note: When oms_agent is enabled with msi_auth_for_monitoring_enabled = true,
# AKS automatically creates:
# - Data Collection Endpoint (DCE)
# - Data Collection Rule (DCR) named "MSCI-<cluster-name>"
# - DCR Association (links AKS to DCR)
# This eliminates the need for manual DCR creation and avoids validation errors.
# ============================================================
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-prod"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_B2s"
  }

  identity {
    type = "SystemAssigned"
  }

  # Enable Container Insights (Azure Monitor Agent)
  # This automatically creates DCR with name: MSCI-<cluster-name>
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.law.id
    msi_auth_for_monitoring_enabled = true
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  tags = var.tags
}

# ============================================================
# 4. Azure AD Application for Grafana
# ============================================================
data "azuread_client_config" "current" {}

resource "azuread_application" "grafana_app" {
  display_name = var.grafana_app_name
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "grafana_sp" {
  client_id = azuread_application.grafana_app.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Use application_password (not service_principal_password) for Grafana client secret
resource "azuread_application_password" "grafana_secret" {
  application_id = azuread_application.grafana_app.id
  display_name   = "Grafana Client Secret"
  end_date       = "2027-02-21T00:00:00Z"
}

# ============================================================
# 5. Role Assignment: Grafana Service Principal → Monitoring Reader
# ============================================================
# This allows Grafana to query logs from Log Analytics Workspace
# using "Resource-Context" authentication (scoped to this RG only)
resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azuread_service_principal.grafana_sp.object_id
}

# ============================================================
# Outputs
# ============================================================

output "grafana_tenant_id" {
  value       = data.azuread_client_config.current.tenant_id
  description = "Grafana: Tenant ID (use in Grafana Azure Monitor datasource)"
}

output "grafana_client_id" {
  value       = azuread_application.grafana_app.client_id
  description = "Grafana: Client ID / Application ID"
}

output "grafana_client_secret" {
  value       = azuread_application_password.grafana_secret.value
  sensitive   = true
  description = "Grafana: Client Secret (use 'terraform output -raw grafana_client_secret' to view)"
}

output "default_subscription_id" {
  value       = data.azurerm_client_config.current.subscription_id
  description = "Grafana: Subscription ID"
}

output "aks_cluster_name" {
  value       = azurerm_kubernetes_cluster.aks.name
  description = "AKS Cluster Name"
}


output "log_analytics_workspace_id" {
  value       = azurerm_log_analytics_workspace.law.id
  description = "Log Analytics Workspace Resource ID"
}

output "log_analytics_workspace_name" {
  value       = azurerm_log_analytics_workspace.law.name
  description = "Log Analytics Workspace Name"
}

output "auto_generated_dcr_name" {
  value       = "MSCI-${azurerm_kubernetes_cluster.aks.name}"
  description = "Auto-generated DCR name (check in Azure Portal → Monitor → Data Collection Rules)"
}

output "aks_system_assigned_identity" {
  value       = azurerm_kubernetes_cluster.aks.identity[0].principal_id
  description = "AKS Managed Identity Principal ID (used for DCR association)"
}
