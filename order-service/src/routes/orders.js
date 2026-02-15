'use strict';

const express = require('express');
const axios = require('axios');
const { v4: uuidv4 } = require('uuid');
const { trace, metrics, SpanStatusCode } = require('@opentelemetry/api');
const logger = require('../logger');

const router = express.Router();

// --- In-memory order store ---
const orders = [];

// --- Custom Metrics ---
const meter = metrics.getMeter('order-service');

// Counter: total orders created
const ordersCreatedCounter = meter.createCounter('orders_created_total', {
    description: 'Total number of orders created',
    unit: '1',
});

// Histogram: order processing duration
const orderDurationHistogram = meter.createHistogram('order_processing_duration_ms', {
    description: 'Time taken to process an order (ms)',
    unit: 'ms',
});

// Counter: failed orders
const ordersFailedCounter = meter.createCounter('orders_failed_total', {
    description: 'Total number of failed order attempts',
    unit: '1',
});

// --- Product Service URL (set via env var in K8s) ---
const PRODUCT_SERVICE_URL = process.env.PRODUCT_SERVICE_URL || 'http://localhost:8080';

/**
 * GET /orders — List all orders
 */
router.get('/', (req, res) => {
    logger.info({ orderCount: orders.length }, 'Listing all orders');
    res.json({
        count: orders.length,
        orders,
    });
});

/**
 * GET /orders/:id — Get order by ID
 */
router.get('/:id', (req, res) => {
    const order = orders.find(o => o.id === req.params.id);
    if (!order) {
        logger.warn({ orderId: req.params.id }, 'Order not found');
        return res.status(404).json({ error: 'Order not found' });
    }
    res.json(order);
});

/**
 * POST /orders — Create a new order
 * Body: { "productId": 1, "quantity": 2 }
 *
 * Flow:
 *   1. Validate request
 *   2. Call Product Service to get product details (GET /products/:id)
 *   3. Call Product Service to reserve stock (PUT /products/:id/reserve)
 *   4. Store order in memory
 *
 * This creates a distributed trace spanning Order Service → Product Service
 */
router.post('/', async (req, res) => {
    const tracer = trace.getTracer('order-service');
    const startTime = Date.now();

    // Create a custom span for the order processing business logic
    return tracer.startActiveSpan('process-order', async (span) => {
        try {
            const { productId, quantity } = req.body;

            // --- Validation ---
            if (!productId || !quantity || quantity < 1) {
                span.setStatus({ code: SpanStatusCode.ERROR, message: 'Invalid request body' });
                ordersFailedCounter.add(1, { reason: 'validation_error' });
                logger.warn({ body: req.body }, 'Invalid order request');
                return res.status(400).json({
                    error: 'Invalid request. Required: { productId: number, quantity: number (>0) }',
                });
            }

            span.setAttribute('order.product_id', productId);
            span.setAttribute('order.quantity', quantity);

            // --- Step 1: Get product details from Product Service ---
            logger.info({ productId }, 'Fetching product details from Product Service');
            let product;
            try {
                const productResponse = await axios.get(`${PRODUCT_SERVICE_URL}/products/${productId}`);
                product = productResponse.data;
                span.addEvent('product_fetched', { 'product.name': product.name, 'product.stock': product.stock });
            } catch (err) {
                span.setStatus({ code: SpanStatusCode.ERROR, message: 'Product not found' });
                ordersFailedCounter.add(1, { reason: 'product_not_found' });
                logger.error({ productId, error: err.message }, 'Failed to fetch product from Product Service');
                return res.status(404).json({
                    error: `Product ${productId} not found or Product Service unavailable`,
                });
            }

            // --- Step 2: Reserve stock in Product Service ---
            logger.info({ productId, quantity }, 'Reserving stock in Product Service');
            try {
                await axios.put(`${PRODUCT_SERVICE_URL}/products/${productId}/reserve`, { quantity });
                span.addEvent('stock_reserved', { quantity });
            } catch (err) {
                span.setStatus({ code: SpanStatusCode.ERROR, message: 'Stock reservation failed' });
                ordersFailedCounter.add(1, { reason: 'insufficient_stock' });
                logger.error({ productId, quantity, error: err.message }, 'Failed to reserve stock');
                return res.status(409).json({
                    error: `Insufficient stock for product ${productId}. Available: ${product.stock}, Requested: ${quantity}`,
                });
            }

            // --- Step 3: Create order ---
            const order = {
                id: uuidv4(),
                productId,
                productName: product.name,
                quantity,
                unitPrice: product.price,
                totalPrice: product.price * quantity,
                status: 'CONFIRMED',
                createdAt: new Date().toISOString(),
            };

            orders.push(order);

            span.setAttribute('order.id', order.id);
            span.setAttribute('order.total_price', order.totalPrice);
            span.setAttribute('order.status', order.status);
            span.setStatus({ code: SpanStatusCode.OK });

            // Record metrics
            const duration = Date.now() - startTime;
            ordersCreatedCounter.add(1, { product_id: String(productId), status: 'CONFIRMED' });
            orderDurationHistogram.record(duration, { product_id: String(productId) });

            logger.info({
                orderId: order.id,
                productId,
                quantity,
                totalPrice: order.totalPrice,
                duration_ms: duration,
            }, 'Order created successfully');

            return res.status(201).json(order);
        } catch (err) {
            span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
            ordersFailedCounter.add(1, { reason: 'internal_error' });
            logger.error({ error: err.message, stack: err.stack }, 'Unexpected error processing order');
            return res.status(500).json({ error: 'Internal server error' });
        } finally {
            span.end();
        }
    });
});

module.exports = router;
