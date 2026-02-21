# Feature2_AMA Branch - Azure Monitor Native Approach

This branch demonstrates **Azure-Native monitoring** using **Azure Monitor Agent (AMA)** and **Application Insights** instead of the OpenTelemetry Collector.

## Key Differences from feature1

| Aspect | feature1 (OTEL) | feature2_AMA (Azure Native) |
|--------|-----------------|-----------------------------|
| **Logs Collection** | OTEL Collector → Log Analytics | AMA DaemonSet → Log Analytics (via DCR) |
| **Traces/Metrics** | OTEL Collector → App Insights | Azure Monitor SDK → App Insights (direct) |
| **Infrastructure** | OTEL Collector pods | AMA DaemonSet (auto-deployed by AKS) |
| **Node.js SDK** | `@opentelemetry/sdk-node` | `@azure/monitor-opentelemetry` |
| **Java Agent** | `opentelemetry-javaagent.jar` | `applicationinsights-agent.jar` |
| **Configuration** | `OTEL_EXPORTER_OTLP_ENDPOINT` | `APPLICATIONINSIGHTS_CONNECTION_STRING` |

## Architecture

```
┌─────────────────┐
│  Order Service   │
│   (Node.js)      │
└────────┬────────┘
         │
         ├─ stdout logs ───────────────────────┐
         │                                      │
         └─ Traces/Metrics ───┐                 │
                              │                 │
┌─────────────────┐       │                 │
│ Product Service │       │                 │
│   (Java)        │       │                 │
└────────┬────────┘       │                 │
         │                 │                 │
         ├─ stdout logs ───────────────────────┤
         │                 │                 │
         └─ Traces/Metrics ─────────────────────┤
                              │                 │
                              │                 │
                              │                 │
                              │                 │
                              │                 │
                              │                 │
                              │                 │
                              │                 │
                   HTTPS      │                 │ TCP via AMA
                              │                 │
                              │                 │
                              ▼                 ▼
                    ┌───────────────────────────────┐
                    │ Application Insights      │
                    │ (Traces + Metrics)        │
                    └───────────────────────────────┘

         ┌──────────────────────────────────────┐
         │ AMA DaemonSet (on every node)        │
         │ Scrapes /var/log/containers/*.log   │
         └────────────┬─────────────────────────┘
                      │
                      │ DCR Filtering
                      │ (drops Debug logs)
                      │
                      ▼
         ┌─────────────────────────────────────┐
         │ Log Analytics Workspace            │
         │ (ContainerLogV2 table)             │
         └─────────────────────────────────────┘
```

## Setup Instructions

### Step 1: Deploy Azure Infrastructure with Terraform

1. **Add Application Insights** to your existing Terraform:
   ```bash
   # Copy the content from terraform-app-insights-addon.tf into your main.tf
   terraform apply
   ```

2. **Get the Application Insights connection string:**
   ```bash
   terraform output -raw app_insights_connection_string
   ```

### Step 2: Configure Kubernetes Secret

1. **Edit `k8s/app-insights-secret.yaml`:**
   ```yaml
   stringData:
     connection-string: "<PASTE_YOUR_CONNECTION_STRING_HERE>"
   ```

2. **Apply the secret:**
   ```bash
   kubectl apply -f k8s/app-insights-secret.yaml
   ```

### Step 3: Update Application Code (Optional)

**For production use, you should update the application code to use Azure Monitor SDKs:**

#### Order Service (Node.js):
```bash
cd order-service
npm uninstall @opentelemetry/exporter-trace-otlp-http
npm install @azure/monitor-opentelemetry --save
```

Update `index.js` or instrumentation file:
```javascript
const { useAzureMonitor } = require("@azure/monitor-opentelemetry");

useAzureMonitor({
  azureMonitorExporterOptions: {
    connectionString: process.env.APPLICATIONINSIGHTS_CONNECTION_STRING
  }
});
```

#### Product Service (Java):

Update `Dockerfile`:
```dockerfile
# Replace OpenTelemetry agent with Application Insights agent
ADD https://github.com/microsoft/ApplicationInsights-Java/releases/download/3.5.0/applicationinsights-agent-3.5.0.jar /app/
ENTRYPOINT ["java", "-javaagent:/app/applicationinsights-agent-3.5.0.jar", "-jar", "/app/app.jar"]
```

### Step 4: Deploy to AKS

```bash
# Create namespace
kubectl apply -f k8s/namespace.yaml

# Apply secret
kubectl apply -f k8s/app-insights-secret.yaml

# Deploy services
kubectl apply -f k8s/product-service-deployment.yaml
kubectl apply -f k8s/product-service-service.yaml
kubectl apply -f k8s/order-service-deployment.yaml
kubectl apply -f k8s/order-service-service.yaml

# Verify
kubectl get pods -n observability-demo
```

### Step 5: Verify Data Flow

#### Logs in Log Analytics:
```bash
# Azure Portal → Log Analytics Workspace → Logs
```

```kusto
ContainerLogV2
| where PodNamespace == "observability-demo"
| where TimeGenerated > ago(10m)
| project TimeGenerated, PodName, LogMessage
| order by TimeGenerated desc
```

#### Traces in Application Insights:
```bash
# Azure Portal → Application Insights → Transaction Search
```

You should see distributed traces showing:
- `order-service` → `product-service` requests
- End-to-end latency
- Dependency calls

## What's Been Removed

- ❌ `k8s/otel-collector-config.yaml`
- ❌ `k8s/otel-collector-deployment.yaml`
- ❌ `k8s/otel-collector-service.yaml`
- ❌ `k8s/otel-configmap.yaml`
- ❌ `k8s/otel-config-multins.yaml`

## What's Been Added

- ✅ `k8s/app-insights-secret.yaml` - Stores Application Insights connection string
- ✅ `terraform-app-insights-addon.tf` - Terraform config for Application Insights
- ✅ Updated deployments with `APPLICATIONINSIGHTS_*` environment variables

## Benefits of This Approach

1. **Simpler Architecture**: No OTEL Collector to manage
2. **Lower Cost**: DCR filters logs at the agent (saves ingestion costs)
3. **Native Integration**: Direct Azure Monitor SDK support
4. **AMA Auto-Management**: DaemonSet is automatically updated by AKS
5. **Resource-Context RBAC**: Grafana can query only specific resource groups

## Grafana Configuration

With this setup, configure two data sources in Grafana SaaS:

1. **Azure Monitor (Logs)**: For `ContainerLogV2` queries
2. **Azure Monitor (Application Insights)**: For traces and metrics

Use the Service Principal credentials from Terraform outputs.

## Cost Optimization

The Data Collection Rule (DCR) in your Terraform filters logs:
```hcl
transform_kql = "source | where LogLevel != 'Debug'"
```

This drops Debug logs **before** they hit Log Analytics, saving ~30-50% on ingestion costs.

## Next Steps

1. Deploy your updated Docker images with Azure Monitor SDKs
2. Create Grafana dashboards for logs + traces correlation
3. Set up alerts in Azure Monitor based on error rates
