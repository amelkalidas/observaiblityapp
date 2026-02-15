package com.demo.productservice.service;

import com.demo.productservice.model.Product;
import com.demo.productservice.repository.ProductRepository;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

@Service
public class ProductService {

    private static final Logger log = LoggerFactory.getLogger(ProductService.class);

    private final ProductRepository repository;
    private final Counter reservedCounter;
    private final Counter reservationFailedCounter;

    public ProductService(ProductRepository repository, MeterRegistry meterRegistry) {
        this.repository = repository;

        // Custom business metrics
        this.reservedCounter = Counter.builder("products_reserved_total")
                .description("Total number of successful stock reservations")
                .register(meterRegistry);

        this.reservationFailedCounter = Counter.builder("products_reservation_failed_total")
                .description("Total number of failed stock reservation attempts")
                .register(meterRegistry);
    }

    public List<Product> findAll() {
        log.info("Fetching all products");
        return repository.findAll();
    }

    public Optional<Product> findById(Long id) {
        log.info("Fetching product with id={}", id);
        return repository.findById(id);
    }

    public Product create(Product product) {
        Product saved = repository.save(product);
        log.info("Created product: id={}, name={}, stock={}", saved.getId(), saved.getName(), saved.getStock());
        return saved;
    }

    /**
     * Reserve stock for a product. Called by Order Service.
     * 
     * @param productId the product ID
     * @param quantity  the quantity to reserve
     * @return the updated product
     * @throws IllegalArgumentException if product not found
     * @throws IllegalStateException    if insufficient stock
     */
    @Transactional
    public Product reserveStock(Long productId, int quantity) {
        log.info("Attempting to reserve stock: productId={}, quantity={}", productId, quantity);

        Product product = repository.findById(productId)
                .orElseThrow(() -> {
                    log.error("Product not found for reservation: id={}", productId);
                    reservationFailedCounter.increment();
                    return new IllegalArgumentException("Product not found: " + productId);
                });

        if (product.getStock() < quantity) {
            log.warn("Insufficient stock: productId={}, available={}, requested={}",
                    productId, product.getStock(), quantity);
            reservationFailedCounter.increment();
            throw new IllegalStateException(
                    String.format("Insufficient stock for product %d. Available: %d, Requested: %d",
                            productId, product.getStock(), quantity));
        }

        product.setStock(product.getStock() - quantity);
        Product updated = repository.save(product);

        reservedCounter.increment();
        log.info("Stock reserved successfully: productId={}, quantity={}, remainingStock={}",
                productId, quantity, updated.getStock());

        return updated;
    }
}
