package com.demo.productservice;

import com.demo.productservice.model.Product;
import com.demo.productservice.repository.ProductRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class ProductServiceApplication {

    private static final Logger log = LoggerFactory.getLogger(ProductServiceApplication.class);

    public static void main(String[] args) {
        SpringApplication.run(ProductServiceApplication.class, args);
    }

    /**
     * Seed sample products on startup so the Order Service has data to work with.
     */
    @Bean
    CommandLineRunner seedData(ProductRepository repository) {
        return args -> {
            if (repository.count() == 0) {
                repository.save(new Product("Widget", 9.99, 100));
                repository.save(new Product("Gadget", 24.99, 50));
                repository.save(new Product("Doohickey", 4.99, 200));
                repository.save(new Product("Thingamajig", 14.99, 75));
                repository.save(new Product("Whatchamacallit", 39.99, 30));
                log.info("Seeded 5 sample products into H2 database");
            }
        };
    }
}
