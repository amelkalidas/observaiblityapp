# ---- Build Stage ----
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev

# ---- Run Stage ----
FROM node:20-alpine
WORKDIR /app

# Security: run as non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy dependencies and source
COPY --from=builder /app/node_modules ./node_modules
COPY package*.json ./
COPY src/ ./src/

# Set ownership
RUN chown -R appuser:appgroup /app
USER appuser

# Environment variables (defaults — override in K8s ConfigMap)
ENV PORT=3000
ENV OTEL_SERVICE_NAME=order-service
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
ENV PRODUCT_SERVICE_URL=http://product-service:8080
ENV LOG_LEVEL=info
ENV NODE_ENV=production

EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Start with tracing preloaded
CMD ["node", "--require", "./src/tracing.js", "src/index.js"]
