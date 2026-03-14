"""
Complete Observability Sample App
Demonstrates: Prometheus metrics, structured logging, Jaeger tracing
"""

import time
import random
import logging
import json
import os
from datetime import datetime

from flask import Flask, request, jsonify, g
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.sdk.resources import Resource

# ─── Structured JSON Logger ────────────────────────────────────────────────────
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "service": "sample-app",
            "message": record.getMessage(),
            "module": record.module,
            "line": record.lineno,
        }
        if hasattr(record, "extra"):
            log_entry.update(record.extra)
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_entry)

handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger = logging.getLogger("sample-app")
logger.setLevel(logging.DEBUG)
logger.addHandler(handler)
logger.propagate = False

# ─── OpenTelemetry / Jaeger Setup ──────────────────────────────────────────────
resource = Resource.create({"service.name": "sample-app", "service.version": "1.0.0"})
provider = TracerProvider(resource=resource)

jaeger_exporter = JaegerExporter(
    agent_host_name=os.getenv("JAEGER_AGENT_HOST", "jaeger"),
    agent_port=int(os.getenv("JAEGER_AGENT_PORT", 6831)),
)
provider.add_span_processor(BatchSpanProcessor(jaeger_exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("sample-app")

# ─── Flask App ─────────────────────────────────────────────────────────────────
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

# ─── Prometheus Metrics ────────────────────────────────────────────────────────
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP request count",
    ["method", "endpoint", "status_code"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]
)
ACTIVE_REQUESTS = Gauge(
    "http_active_requests",
    "Number of active HTTP requests"
)
ERROR_COUNT = Counter(
    "app_errors_total",
    "Total application errors",
    ["error_type"]
)
DB_QUERY_LATENCY = Histogram(
    "db_query_duration_seconds",
    "Simulated database query latency",
    ["operation"]
)
BUSINESS_ORDERS = Counter(
    "business_orders_total",
    "Total orders processed",
    ["status"]
)

# ─── Middleware ────────────────────────────────────────────────────────────────
@app.before_request
def before_request():
    g.start_time = time.time()
    ACTIVE_REQUESTS.inc()
    logger.info("Request started", extra={"extra": {
        "method": request.method,
        "path": request.path,
        "remote_addr": request.remote_addr,
        "trace_id": _get_trace_id()
    }})

@app.after_request
def after_request(response):
    latency = time.time() - g.start_time
    ACTIVE_REQUESTS.dec()
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.path,
        status_code=response.status_code
    ).inc()
    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.path
    ).observe(latency)
    logger.info("Request completed", extra={"extra": {
        "method": request.method,
        "path": request.path,
        "status_code": response.status_code,
        "latency_ms": round(latency * 1000, 2),
        "trace_id": _get_trace_id()
    }})
    return response

def _get_trace_id():
    span = trace.get_current_span()
    ctx = span.get_span_context()
    return format(ctx.trace_id, "032x") if ctx.is_valid else "none"

# ─── Routes ───────────────────────────────────────────────────────────────────
@app.route("/")
def index():
    with tracer.start_as_current_span("index-handler"):
        logger.info("Home endpoint accessed")
        return jsonify({
            "service": "observability-demo",
            "status": "running",
            "endpoints": ["/api/users", "/api/orders", "/api/products", "/api/slow", "/metrics", "/health"]
        })

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "timestamp": datetime.utcnow().isoformat()})

@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

@app.route("/api/users")
def get_users():
    with tracer.start_as_current_span("get-users") as span:
        users = _simulate_db_query("SELECT", "users", span)
        logger.info("Users fetched", extra={"extra": {"count": len(users), "trace_id": _get_trace_id()}})
        return jsonify({"users": users, "total": len(users)})

@app.route("/api/users/<int:user_id>")
def get_user(user_id):
    with tracer.start_as_current_span("get-user-by-id") as span:
        span.set_attribute("user.id", user_id)
        if user_id > 100:
            ERROR_COUNT.labels(error_type="not_found").inc()
            logger.warning("User not found", extra={"extra": {"user_id": user_id}})
            return jsonify({"error": "User not found"}), 404
        user = {"id": user_id, "name": f"User_{user_id}", "email": f"user{user_id}@example.com"}
        return jsonify(user)

@app.route("/api/orders", methods=["GET", "POST"])
def orders():
    with tracer.start_as_current_span("orders-handler") as span:
        if request.method == "POST":
            order_id = random.randint(1000, 9999)
            status = random.choice(["confirmed", "pending", "failed"])
            BUSINESS_ORDERS.labels(status=status).inc()
            span.set_attribute("order.id", order_id)
            span.set_attribute("order.status", status)
            logger.info("Order created", extra={"extra": {"order_id": order_id, "status": status}})
            return jsonify({"order_id": order_id, "status": status}), 201
        orders = _simulate_db_query("SELECT", "orders", span)
        return jsonify({"orders": orders, "total": len(orders)})

@app.route("/api/products")
def get_products():
    with tracer.start_as_current_span("get-products") as span:
        # Simulate cache check then DB
        with tracer.start_as_current_span("cache-lookup"):
            time.sleep(random.uniform(0.001, 0.005))
            cache_hit = random.random() > 0.6
            span.set_attribute("cache.hit", cache_hit)

        if not cache_hit:
            with tracer.start_as_current_span("db-query"):
                products = _simulate_db_query("SELECT", "products", span)
        else:
            products = [{"id": i, "name": f"Product_{i}", "price": round(random.uniform(9.99, 99.99), 2)}
                        for i in range(1, 6)]
        logger.debug("Products fetched", extra={"extra": {"cache_hit": cache_hit, "count": len(products)}})
        return jsonify({"products": products, "cache_hit": cache_hit})

@app.route("/api/slow")
def slow_endpoint():
    """Simulates a slow endpoint for latency testing"""
    with tracer.start_as_current_span("slow-endpoint") as span:
        delay = random.uniform(0.5, 3.0)
        span.set_attribute("simulated.delay_seconds", delay)
        logger.warning("Slow request detected", extra={"extra": {"expected_delay_ms": round(delay * 1000)}})
        time.sleep(delay)
        return jsonify({"message": "Slow response completed", "delay_seconds": round(delay, 3)})

@app.route("/api/error")
def error_endpoint():
    """Simulates random errors for testing alerting"""
    with tracer.start_as_current_span("error-endpoint") as span:
        error_type = random.choice(["database_timeout", "validation_error", "external_api_error"])
        ERROR_COUNT.labels(error_type=error_type).inc()
        span.set_attribute("error", True)
        span.set_attribute("error.type", error_type)
        logger.error("Application error occurred", extra={"extra": {"error_type": error_type}})
        return jsonify({"error": error_type, "message": "Simulated error for testing"}), 500

def _simulate_db_query(operation, table, span):
    with tracer.start_as_current_span(f"db-{operation.lower()}-{table}"):
        latency = random.uniform(0.005, 0.08)
        time.sleep(latency)
        DB_QUERY_LATENCY.labels(operation=f"{operation}_{table}").observe(latency)
        span.set_attribute(f"db.table", table)
        span.set_attribute(f"db.operation", operation)
        count = random.randint(3, 15)
        return [{"id": i, "table": table, "data": f"record_{i}"} for i in range(1, count + 1)]

if __name__ == "__main__":
    logger.info("Starting observability demo application", extra={"extra": {"port": 5000}})
    app.run(host="0.0.0.0", port=5000, debug=False)
