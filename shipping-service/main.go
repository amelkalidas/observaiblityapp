package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
	"go.opentelemetry.io/otel/trace"
)

var tracer trace.Tracer

func initTracer() *sdktrace.TracerProvider {
	ctx := context.Background()
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "otel-collector:4318"
	}

	exporter, err := otlptracehttp.New(ctx, 
		otlptracehttp.WithEndpoint(endpoint),
		otlptracehttp.WithInsecure(),
	)
	if err != nil {
		log.Fatal(err)
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceNameKey.String("shipping-service"),
		),
	)
	if err != nil {
		log.Fatal(err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	tracer = tp.Tracer("shipping-service")
	return tp
}

func main() {
	tp := initTracer()
	defer func() { _ = tp.Shutdown(context.Background()) }()

	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(otelgin.Middleware("shipping-service"))

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "UP"})
	})

	// Shipping cost and tracking
	r.POST("/calculate", func(c *gin.Context) {
		var req struct {
			Quantity int `json:"quantity"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
			return
		}

		span := trace.SpanFromContext(c.Request.Context())
		span.SetAttributes(attribute.Int("shipping.quantity", req.Quantity))

		// Simulate business logic
		cost := float64(req.Quantity) * 5.99
		trackingID := uuid.New().String()

		fmt.Printf("{\"level\":\"info\",\"msg\":\"Calculating shipping\",\"tracking_id\":\"%s\",\"cost\":%f,\"trace_id\":\"%s\"}\n", 
			trackingID, cost, span.SpanContext().TraceID().String())

		time.Sleep(time.Duration(10+rand.Intn(50)) * time.Millisecond) // Simulate latency

		c.JSON(http.StatusOK, gin.H{
			"tracking_id": trackingID,
			"cost":        cost,
			"status":      "SHIPPED",
		})
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "5000"
	}
	log.Printf("Shipping Service starting on port %s", port)
	r.Run(":" + port)
}
