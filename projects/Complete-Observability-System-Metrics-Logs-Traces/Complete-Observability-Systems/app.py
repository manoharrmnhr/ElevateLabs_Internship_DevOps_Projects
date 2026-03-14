import time
import random
import logging
import json
import os
from flask import Flask, request, jsonify
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.resources import Resource

# ── Structured JSON Logger ──────────────────────────────────────────────────
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": self.formatTime(record),
            "level": record.levelname,
            "service": "observability-app",
            "message": record.getMessage(),
            "module": record.module,
            "line": record.lineno,
        }
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_entry)

handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger = logging.getLogger("app")
logger.setLevel(logging.DEBUG)
logger.addHandler(handler)
logger.propagate = False

# ── OpenTelemetry Tracing ───────────────────────────────────────────────────
resource = Resource.create({"service.name": "observability-app", "service.version": "1.0.0"})
provider = TracerProvider(resource=resource)
otlp_endpoint = os.getenv("OTLP_ENDPOINT", "http://jaeger:4318/v1/traces")
exporter = OTLPSpanExporter(endpoint=otlp_endpoint)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# ── Flask App ───────────────────────────────────────────────────────────────
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

# ── Prometheus Metrics ──────────────────────────────────────────────────────
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "endpoint"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
)
ACTIVE_REQUESTS = Gauge("http_active_requests", "Currently active HTTP requests")
ERROR_COUNT = Counter("http_errors_total", "Total HTTP errors", ["endpoint", "error_type"])
DB_QUERY_DURATION = Histogram(
    "db_query_duration_seconds",
    "Simulated DB query duration",
    ["operation"],
    buckets=[0.001, 0.005, 0.01, 0.05, 0.1, 0.5]
)

# ── Middleware ──────────────────────────────────────────────────────────────
@app.before_request
def before_request():
    request.start_time = time.time()
    ACTIVE_REQUESTS.inc()
    logger.info(f"Incoming request: {request.method} {request.path} from {request.remote_addr}")

@app.after_request
def after_request(response):
    duration = time.time() - request.start_time
    ACTIVE_REQUESTS.dec()
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.path,
        status=response.status_code
    ).inc()
    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.path
    ).observe(duration)
    logger.info(
        f"Completed {request.method} {request.path} → {response.status_code} in {duration:.4f}s"
    )
    return response

# ── Routes ──────────────────────────────────────────────────────────────────
@app.route("/")
def index():
    logger.info("Health check endpoint called")
    return jsonify({"status": "ok", "service": "observability-app", "version": "1.0.0"})

@app.route("/api/users")
def get_users():
    with tracer.start_as_current_span("get_users") as span:
        logger.info("Fetching user list")
        latency = random.uniform(0.02, 0.15)
        with tracer.start_as_current_span("db.query.users"):
            DB_QUERY_DURATION.labels(operation="SELECT").observe(latency)
            time.sleep(latency)
        users = [
            {"id": i, "name": f"User_{i}", "email": f"user{i}@example.com"}
            for i in range(1, random.randint(5, 20))
        ]
        span.set_attribute("user.count", len(users))
        logger.info(f"Returned {len(users)} users")
        return jsonify({"users": users, "count": len(users)})

@app.route("/api/orders")
def get_orders():
    with tracer.start_as_current_span("get_orders") as span:
        logger.info("Processing orders request")
        # Simulate occasional slow queries
        if random.random() < 0.2:
            logger.warning("Slow DB query detected for orders")
            latency = random.uniform(0.5, 1.5)
        else:
            latency = random.uniform(0.01, 0.1)
        with tracer.start_as_current_span("db.query.orders"):
            DB_QUERY_DURATION.labels(operation="SELECT").observe(latency)
            time.sleep(latency)
        orders = [
            {"id": i, "product": f"Product_{random.randint(1,50)}", "amount": round(random.uniform(10, 500), 2)}
            for i in range(random.randint(1, 10))
        ]
        span.set_attribute("order.count", len(orders))
        return jsonify({"orders": orders, "count": len(orders)})

@app.route("/api/process", methods=["POST"])
def process_data():
    with tracer.start_as_current_span("process_data") as span:
        logger.info("Processing POST data")
        data = request.get_json(silent=True) or {}
        # Simulate processing steps
        with tracer.start_as_current_span("validate_input"):
            time.sleep(random.uniform(0.005, 0.02))
        with tracer.start_as_current_span("transform_data"):
            time.sleep(random.uniform(0.01, 0.05))
        with tracer.start_as_current_span("db.write"):
            latency = random.uniform(0.01, 0.08)
            DB_QUERY_DURATION.labels(operation="INSERT").observe(latency)
            time.sleep(latency)
        span.set_attribute("input.keys", str(list(data.keys())))
        logger.info(f"Successfully processed data with keys: {list(data.keys())}")
        return jsonify({"status": "processed", "received_keys": list(data.keys())}), 201

@app.route("/api/error")
def trigger_error():
    error_types = ["DatabaseError", "TimeoutError", "ValidationError"]
    chosen = random.choice(error_types)
    logger.error(f"Simulated error triggered: {chosen}", extra={"error_type": chosen})
    ERROR_COUNT.labels(endpoint="/api/error", error_type=chosen).inc()
    return jsonify({"error": chosen, "message": "Simulated error for observability demo"}), 500

@app.route("/api/slow")
def slow_endpoint():
    delay = random.uniform(1.0, 3.0)
    logger.warning(f"Slow endpoint called, sleeping {delay:.2f}s")
    with tracer.start_as_current_span("slow_operation"):
        time.sleep(delay)
    return jsonify({"message": "slow response", "delay_seconds": round(delay, 2)})

@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "uptime": time.time()})

if __name__ == "__main__":
    logger.info("Starting observability-app on port 5000")
    app.run(host="0.0.0.0", port=5000, debug=False)
