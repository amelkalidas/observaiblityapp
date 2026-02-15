# AKS Observability Demo — Microservices with OpenTelemetry

Two microservices fully instrumented with **OpenTelemetry** for distributed tracing, metrics, and structured logging — designed for learning observability in **Azure Kubernetes Service (AKS)**.

## Architecture

```
┌─────────────────┐     HTTP      ┌──────────────────┐
│  Order Service   │──────────────▶│  Product Service  │
│  (Node.js:3000)  │              │  (Java:8080)      │
│                  │              │  + H2 Database    │
└────────┬─────────┘              └────────┬──────────┘
         │                                 │
         │ OTLP traces/metrics             │ OTLP traces/metrics
         │ JSON logs → stdout              │ JSON logs → stdout
         ▼                                 ▼
┌─────────────────────────────────────────────────────┐
│              OTEL Collector / Container Insights      │
│         ↓                    ↓                  ↓     │
│   Azure App Insights   Log Analytics   Managed Prometheus │
└─────────────────────────────────────────────────────┘
```

## Services

| Service | Language | Port | Description |
|---------|----------|------|-------------|
| **order-service** | Node.js + Express | 3000 | Accepts orders, calls Product Service to validate & reserve stock |
| **product-service** | Java + Spring Boot | 8080 | CRUD products, inventory management, H2 in-memory DB |

## Telemetry Emitted

| Signal | Order Service | Product Service |
|--------|--------------|-----------------|
| **Traces** | HTTP/Express auto-spans + custom `process-order` span | HTTP/Spring + JDBC auto-spans (Java Agent) |
| **Metrics** | `orders_created_total`, `order_processing_duration_ms`, `orders_failed_total` | `http_server_requests`, `products_reserved_total`, JVM metrics |
| **Logs** | JSON via Pino with `trace_id`/`span_id` | JSON via Logback with `trace_id`/`span_id` |

## Quick Start (Local Development)

### Prerequisites
- Node.js 20+
- Java 21+ and Maven 3.9+
- Docker (optional, for container builds)

### 1. Start Product Service (Java)
```bash
cd product-service
mvn spring-boot:run
```
Starts on `http://localhost:8080` with 5 pre-seeded products.

### 2. Start Order Service (Node.js)
```bash
cd order-service
npm install
npm start
```
Starts on `http://localhost:3000`.

### 3. Test the Flow
```bash
# List products (pre-seeded)
curl http://localhost:8080/products

# Create an order (triggers distributed trace across both services)
curl -X POST http://localhost:3000/orders \
  -H "Content-Type: application/json" \
  -d '{"productId": 1, "quantity": 2}'

# List orders
curl http://localhost:3000/orders

# Check stock decreased
curl http://localhost:8080/products/1
```

### 4. Verify Logs
Check stdout of both services — you should see JSON log lines with `trace_id` and `span_id`:
```json
{"level":"info","time":"2025-01-15T10:30:00.000Z","service_name":"order-service","trace_id":"abc123...","span_id":"def456...","orderId":"...","msg":"Order created successfully"}
```

## Docker Build

```bash
# Order Service
docker build -t order-service:1.0.0 ./order-service

# Product Service
docker build -t product-service:1.0.0 ./product-service

# Run together
docker run -d --name product-service -p 8080:8080 product-service:1.0.0
docker run -d --name order-service -p 3000:3000 \
  -e PRODUCT_SERVICE_URL=http://host.docker.internal:8080 \
  order-service:1.0.0
```

## Deploy to AKS (🔧 Admin)

```bash
# Create namespace
kubectl apply -f k8s/namespace.yaml

# Deploy OTEL config
kubectl apply -f k8s/otel-configmap.yaml

# Deploy services
kubectl apply -f k8s/product-service-deployment.yaml
kubectl apply -f k8s/product-service-service.yaml
kubectl apply -f k8s/order-service-deployment.yaml
kubectl apply -f k8s/order-service-service.yaml

# Verify
kubectl get pods -n observability-demo
```

## Role Responsibilities

| Task | 🧑‍💻 Developer | 🔧 Admin |
|------|:-----------:|:-----------:|
| Application code & OTEL SDK | ✅ | |
| Structured JSON logging | ✅ | |
| Health check endpoints | ✅ | |
| Dockerfile | ✅ | Reviews |
| K8s manifests & probes | | ✅ |
| OTEL ConfigMap (endpoints) | | ✅ |
| OTEL Collector deployment | | ✅ |
| Azure Monitor / App Insights setup | | ✅ |
| Grafana dashboards & alerts | | ✅ |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OTEL_SERVICE_NAME` | `order-service` / `product-service` | Service identity in traces |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | OTEL Collector endpoint |
| `PRODUCT_SERVICE_URL` | `http://localhost:8080` | Product Service URL (Order Service only) |
| `LOG_LEVEL` | `info` | Log verbosity |
| `PORT` | `3000` | Order Service port |
