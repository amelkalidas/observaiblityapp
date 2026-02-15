'use strict';

const pino = require('pino');
const api = require('@opentelemetry/api');

/**
 * Creates a Pino JSON logger that automatically injects OpenTelemetry
 * trace context (trace_id, span_id) into every log line.
 *
 * This enables log ↔ trace correlation in Application Insights, Grafana, etc.
 * Fluentd/Fluent Bit can parse these JSON logs directly from container stdout.
 */
const logger = pino({
    level: process.env.LOG_LEVEL || 'info',
    // All fields are output as flat JSON — ideal for Fluentd/Fluent Bit parsing
    formatters: {
        level(label) {
            return { level: label };
        },
        log(object) {
            // Inject OTEL trace context into every log line
            const span = api.trace.getActiveSpan();
            if (span) {
                const spanContext = span.spanContext();
                object.trace_id = spanContext.traceId;
                object.span_id = spanContext.spanId;
                object.trace_flags = spanContext.traceFlags;
            }
            return object;
        },
    },
    // Add static fields
    base: {
        service_name: process.env.OTEL_SERVICE_NAME || 'order-service',
        pid: process.pid,
    },
    timestamp: pino.stdTimeFunctions.isoTime,
});

module.exports = logger;
