'use strict';

const express = require('express');
const logger = require('./logger');
const orderRoutes = require('./routes/orders');

const app = express();
const PORT = process.env.PORT || 3000;

// --- Middleware ---
app.use(express.json());

// Request logging middleware — logs every incoming request with trace context
app.use((req, res, next) => {
    const start = Date.now();
    res.on('finish', () => {
        const duration = Date.now() - start;
        logger.info({
            method: req.method,
            path: req.path,
            status_code: res.statusCode,
            duration_ms: duration,
            user_agent: req.get('User-Agent'),
        }, `${req.method} ${req.path} ${res.statusCode} ${duration}ms`);
    });
    next();
});

// --- Routes ---
app.use('/orders', orderRoutes);

// Health check endpoint (used by K8s liveness/readiness probes)
app.get('/health', (req, res) => {
    res.json({
        status: 'UP',
        service: 'order-service',
        timestamp: new Date().toISOString(),
    });
});

// Root endpoint
app.get('/', (req, res) => {
    res.json({
        service: 'order-service',
        version: '1.0.0',
        endpoints: [
            'GET  /health',
            'GET  /orders',
            'GET  /orders/:id',
            'POST /orders',
        ],
    });
});

// --- Start Server ---
app.listen(PORT, () => {
    logger.info({ port: PORT }, `Order Service started on port ${PORT}`);
});

module.exports = app;
