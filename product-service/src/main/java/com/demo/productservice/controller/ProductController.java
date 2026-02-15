package com.demo.productservice.controller;

import com.demo.productservice.model.Product;
import com.demo.productservice.service.ProductService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/products")
public class ProductController {

    private static final Logger log = LoggerFactory.getLogger(ProductController.class);

    private final ProductService productService;

    public ProductController(ProductService productService) {
        this.productService = productService;
    }

    /**
     * GET /products — List all products
     */
    @GetMapping
    public ResponseEntity<List<Product>> getAllProducts() {
        log.info("GET /products — listing all products");
        List<Product> products = productService.findAll();
        return ResponseEntity.ok(products);
    }

    /**
     * GET /products/{id} — Get product by ID
     */
    @GetMapping("/{id}")
    public ResponseEntity<?> getProductById(@PathVariable Long id) {
        log.info("GET /products/{} — fetching product", id);
        return productService.findById(id)
                .map(product -> ResponseEntity.ok((Object) product))
                .orElseGet(() -> {
                    log.warn("Product not found: id={}", id);
                    return ResponseEntity.status(HttpStatus.NOT_FOUND)
                            .body(Map.of("error", "Product not found: " + id));
                });
    }

    /**
     * POST /products — Create a new product
     * Body: { "name": "Widget", "price": 9.99, "stock": 100 }
     */
    @PostMapping
    public ResponseEntity<Product> createProduct(@RequestBody Product product) {
        log.info("POST /products — creating product: name={}", product.getName());
        Product created = productService.create(product);
        return ResponseEntity.status(HttpStatus.CREATED).body(created);
    }

    /**
     * PUT /products/{id}/reserve — Reserve stock (called by Order Service)
     * Body: { "quantity": 2 }
     */
    @PutMapping("/{id}/reserve")
    public ResponseEntity<?> reserveStock(@PathVariable Long id, @RequestBody Map<String, Integer> body) {
        int quantity = body.getOrDefault("quantity", 0);
        log.info("PUT /products/{}/reserve — reserving quantity={}", id, quantity);

        try {
            Product updated = productService.reserveStock(id, quantity);
            return ResponseEntity.ok(updated);
        } catch (IllegalArgumentException e) {
            log.error("Reserve failed — product not found: id={}", id);
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", e.getMessage()));
        } catch (IllegalStateException e) {
            log.warn("Reserve failed — insufficient stock: id={}, quantity={}", id, quantity);
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("error", e.getMessage()));
        }
    }
}
