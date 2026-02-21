# ============================================================
# Application Insights - Add this to your main.tf
# ============================================================
# This resource creates Azure Application Insights for distributed tracing
# and metrics from your microservices using the Azure Monitor SDK.
#
# USAGE:
# 1. Add this block to your existing main.tf (from the AKS setup)
# 2. Run: terraform apply
# 3. Get the connection string: terraform output -raw app_insights_connection_string
# 4. Update k8s/app-insights-secret.yaml with the connection string
# ============================================================

resource "azurerm_application_insights" "app_insights" {
  name                = "${var.cluster_name}-insights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.law.id
  tags                = var.tags
}

output "app_insights_connection_string" {
  value       = azurerm_application_insights.app_insights.connection_string
  sensitive   = true
  description = "Copy this to k8s/app-insights-secret.yaml"
}

output "app_insights_instrumentation_key" {
  value       = azurerm_application_insights.app_insights.instrumentation_key
  sensitive   = true
  description = "Legacy instrumentation key (use connection_string instead)"
}
