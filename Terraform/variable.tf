variable "tenant_id" {
  default = "60e568d9-7f02-4a3a-a8a4-21e083d4a0b4"
}
variable "subscription_id" {
  default = "6c994f76-5e6b-4c94-be90-2e4b8f714ef7"
  
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the Resource Group"
  type        = string
  default     = "rg-aks-monitoring-prod"
}

variable "cluster_name" {
  description = "Name of the AKS Cluster"
  type        = string
  default     = "aks-prod-cluster"
}

variable "log_analytics_name" {
  description = "Name of the Log Analytics Workspace"
  type        = string
  default     = "law-aks-prod-logs"
}

variable "grafana_app_name" {
  description = "Name of the Azure AD App for Grafana SaaS"
  type        = string
  default     = "grafana-saas-reader-app"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "Production"
    Project     = "AKS-Monitoring"
  }
}
