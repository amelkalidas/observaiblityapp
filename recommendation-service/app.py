import os
import random
import time
import logging
import json
from flask import Flask, request, jsonify
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

# Initialize Flask app
app = Flask(__name__)

# Setup OpenTelemetry
resource = Resource(attributes={"service.name": "recommendation-service"})
provider = TracerProvider(resource=resource)
otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4318")
processor = BatchSpanProcessor(OTLPSpanExporter(endpoint=f"{otlp_endpoint}/v1/traces"))
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# Instrument Flask
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

# Custom JSON Logger
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_record = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "message": record.getMessage(),
            "service_name": "recommendation-service",
            "trace_id": trace.format_trace_id(trace.get_current_span().get_span_context().trace_id) if trace.get_current_span().get_span_context().is_valid else None
        }
        return json.dumps(log_record)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("recommendation-service")
handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
logger.handlers = [handler]
logger.propagate = False

@app.route('/health')
def health():
    return jsonify(status="UP")

@app.route('/recommendations/<int:product_id>')
def get_recommendations(product_id):
    span = trace.get_current_span()
    span.set_attribute("recommendation.product_id", product_id)
    
    logger.info(f"Generating recommendations for product {product_id}")
    
    # Mock database
    recommendations = [
        {"id": 101, "name": "Basic Case", "price": 15.0},
        {"id": 102, "name": "Screen Protector", "price": 9.99},
        {"id": 103, "name": "Fast Charger", "price": 25.0}
    ]
    
    # Randomly select 2 recommendations
    selected = random.sample(recommendations, 2)
    
    time.sleep(random.uniform(0.01, 0.05)) # Simulate DB call
    
    return jsonify({
        "product_id": product_id,
        "recommendations": selected
    })

if __name__ == '__main__':
    port = int(os.getenv("PORT", 6000))
    app.run(host='0.0.0.0', port=port)
