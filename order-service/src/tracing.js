'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { Resource } = require('@opentelemetry/resources');
const { SEMRESATTRS_SERVICE_NAME, SEMRESATTRS_SERVICE_VERSION } = require('@opentelemetry/semantic-conventions');

// --- Configuration via environment variables ---
const OTEL_EXPORTER_OTLP_ENDPOINT = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318';
const SERVICE_NAME = process.env.OTEL_SERVICE_NAME || 'order-service';

// --- Resource: identifies this service in traces/metrics ---
const resource = new Resource({
  [SEMRESATTRS_SERVICE_NAME]: SERVICE_NAME,
  [SEMRESATTRS_SERVICE_VERSION]: '1.0.0',
  'deployment.environment': process.env.OTEL_ENVIRONMENT || 'development',
});

// --- Trace Exporter (OTLP/HTTP) ---
const traceExporter = new OTLPTraceExporter({
  url: `${OTEL_EXPORTER_OTLP_ENDPOINT}/v1/traces`,
});

// --- Metric Exporter (OTLP/HTTP) ---
const metricExporter = new OTLPMetricExporter({
  url: `${OTEL_EXPORTER_OTLP_ENDPOINT}/v1/metrics`,
});

const metricReader = new PeriodicExportingMetricReader({
  exporter: metricExporter,
  exportIntervalMillis: 15000, // export metrics every 15 seconds
});

// --- Initialize OpenTelemetry SDK ---
const sdk = new NodeSDK({
  resource,
  traceExporter,
  metricReader,
  instrumentations: [
    getNodeAutoInstrumentations({
      // Auto-instrument HTTP (axios calls to Product Service) and Express
      '@opentelemetry/instrumentation-http': { enabled: true },
      '@opentelemetry/instrumentation-express': { enabled: true },
      // Disable fs instrumentation (too noisy)
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
  ],
});

sdk.start();
console.log(`[OTEL] Tracing initialized for service: ${SERVICE_NAME}`);
console.log(`[OTEL] Exporting to: ${OTEL_EXPORTER_OTLP_ENDPOINT}`);

// Graceful shutdown
process.on('SIGTERM', () => {
  sdk.shutdown()
    .then(() => console.log('[OTEL] SDK shut down successfully'))
    .catch((err) => console.error('[OTEL] Error shutting down SDK', err))
    .finally(() => process.exit(0));
});
