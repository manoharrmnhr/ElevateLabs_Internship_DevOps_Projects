#!/usr/bin/env python3
"""
Instrumented Python Application for Complete Observability System
Integrates Prometheus metrics, structured logging, and Jaeger tracing
"""

import logging
import json
import time
import random
from datetime import datetime
from typing import Dict, Any

from flask import Flask, request, jsonify
from prometheus_client import Counter, Histogram, Gauge, generate_latest, REGISTRY
from prometheus_client.core import CollectorRegistry
from pythonjsonlogger import jsonlogger
from jaeger_client import Config
from opentelemetry import trace, metrics
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.prometheus import PrometheusMetricReader
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

# Initialize Flask app
app = Flask(__name__)

# ============================================================================
# LOGGING SETUP
# ============================================================================
def setup_logging():
    """Configure structured JSON logging to stdout"""
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    
    # JSON formatter for structured logs
    handler = logging.StreamHandler()
    formatter = jsonlogger.JsonFormatter(
        '%(timestamp)s %(name)s %(levelname)s %(message)s %(funcName)s %(lineno)d'
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    
    return logger

logger = setup_logging()

# ============================================================================
# JAEGER TRACING SETUP
# ============================================================================
def init_jaeger_tracer():
    """Initialize Jaeger tracer with OpenTelemetry"""
    config = Config(
        config={
            'sampler': {
                'type': 'const',
                'param': 1,
            },
            'logging': True,
            'local_agent': {
                'reporting_host': 'jaeger',
                'reporting_port': 6831,
            }
        },
        service_name='observability-app',
        validate=True,
    )
    return config.initialize_tracer()

# Initialize Jaeger tracer
jaeger_tracer = init_jaeger_tracer()

# Setup OpenTelemetry for Flask instrumentation
jaeger_exporter = JaegerExporter(
    agent_host_name="jaeger",
    agent_port=6831,
)

trace.set_tracer_provider(
    TracerProvider(
        span_processor=BatchSpanProcessor(jaeger_exporter)
    )
)

# Instrument Flask and requests
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

# ============================================================================
# PROMETHEUS METRICS SETUP
# ============================================================================
registry = CollectorRegistry()

# Custom metrics
request_counter = Counter(
    'app_requests_total',
    'Total number of requests',
    ['method', 'endpoint', 'status'],
    registry=registry
)

request_duration = Histogram(
    'app_request_duration_seconds',
    'Request duration in seconds',
    ['method', 'endpoint'],
    buckets=(0.1, 0.5, 1.0, 2.5, 5.0, 10.0),
    registry=registry
)

active_requests = Gauge(
    'app_active_requests',
    'Number of active requests',
    registry=registry
)

custom_events = Counter(
    'app_events_total',
    'Total custom events',
    ['event_type'],
    registry=registry
)

api_errors = Counter(
    'app_errors_total',
    'Total errors by type',
    ['error_type', 'endpoint'],
    registry=registry
)

processing_time = Histogram(
    'app_processing_time_seconds',
    'Processing time for business logic',
    ['operation'],
    buckets=(0.01, 0.05, 0.1, 0.5, 1.0),
    registry=registry
)

# ============================================================================
# HEALTH CHECK ENDPOINT
# ============================================================================
@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    logger.info('Health check requested', extra={
        'timestamp': datetime.utcnow().isoformat(),
        'endpoint': '/health'
    })
    return jsonify({'status': 'healthy', 'timestamp': datetime.utcnow().isoformat()}), 200

# ============================================================================
# METRICS ENDPOINT
# ============================================================================
@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(registry), 200, {'Content-Type': 'text/plain; charset=utf-8'}

# ============================================================================
# API ENDPOINTS
# ============================================================================
@app.route('/api/users', methods=['GET'])
def get_users():
    """Get list of users with metrics tracking"""
    start_time = time.time()
    active_requests.inc()
    
    try:
        logger.info('Fetching users list', extra={
            'timestamp': datetime.utcnow().isoformat(),
            'endpoint': '/api/users'
        })
        
        # Simulate processing
        time.sleep(random.uniform(0.1, 0.5))
        
        users = [
            {'id': 1, 'name': 'Alice Johnson', 'email': 'alice@example.com'},
            {'id': 2, 'name': 'Bob Smith', 'email': 'bob@example.com'},
            {'id': 3, 'name': 'Charlie Brown', 'email': 'charlie@example.com'},
        ]
        
        request_counter.labels(method='GET', endpoint='/api/users', status=200).inc()
        custom_events.labels(event_type='users_fetched').inc()
        
        duration = time.time() - start_time
        request_duration.labels(method='GET', endpoint='/api/users').observe(duration)
        processing_time.labels(operation='fetch_users').observe(duration)
        
        logger.info('Users fetched successfully', extra={
            'timestamp': datetime.utcnow().isoformat(),
            'user_count': len(users),
            'duration': duration
        })
        
        return jsonify(users), 200
        
    except Exception as e:
        logger.error('Error fetching users', extra={
            'timestamp': datetime.utcnow().isoformat(),
            'error': str(e)
        })
        request_counter.labels(method='GET', endpoint='/api/users', status=500).inc()
        api_errors.labels(error_type='fetch_error', endpoint='/api/users').inc()
        return jsonify({'error': str(e)}), 500
    finally:
        active_requests.dec()

@app.route('/api/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    """Get single user by ID"""
    start_time = time.time()
    active_requests.inc()
    
    try:
        logger.info('Fetching user', extra={
            'timestamp': datetime.utcnow().isoformat(),
            'user_id': user_id,
            'endpoint': '/api/users/<id>'
        })
        
        if user_id < 1 or user_id > 3:
            logger.warning('User not found', extra={
                'timestamp': datetime.utcnow().isoformat(),
                'user_id': user_id
            })
            request_counter.labels(method='GET', endpoint='/api/users/<id>', status=404).inc()
            return jsonify({'error': 'User not found'}), 404
        
        users = {
            1: {'id': 1, 'name': 'Alice Johnson', 'email': 'alice@example.com'},
            2: {'id': 2, 'name': 'Bob Smith', 'email': 'bob@example.com'},
            3: {'id': 3, 'name': 'Charlie Brown', 'email': 'charlie@example.com'},
        }
        
        time.sleep(random.uniform(0.05, 0.2))
        
        request_counter.labels(method='GET', endpoint='/api/users/<id>', status=200).inc()
        custom_events.labels(event_type='user_retrieved').inc()
        
        duration = time.time() - start_time
        request_duration.labels(method='GET', endpoint='/api/users/<id>').observe(duration)
        processing_time.labels(operation='get_user').observe(duration)
        
        return jsonify(users[user_id]), 200
        
    except Exception as e:
        logger.error('Error fetching user', extra={
            'timestamp': datetime.utcnow().isoformat(),
            'user_id': user_id,
            'error': str(e)
        })
        request_counter.labels(method='GET', endpoint='/api/users/<id>', status=500).inc()
        api_errors.labels(error_type='fetch_error', endpoint='/api/users/<id>').inc()
        return jsonify({'error': str(e)}), 500
    finally:
        active_requests.dec()

@app.route('/api/process', methods=['POST'])
def process_data():
    """Process data with variable execution time"""
    start_time = time.time()
    active_requests.inc()
    
    try:
        data = request.get_json()
        
        logger.info('Processing data', extra={
            'timestamp': datetime.utcnow().isoformat(),
            'endpoint': '/api/process',
            'data_size': len(str(data))
        })
        
        # Simulate variable processing time
        processing_duration = random.uniform(0.5, 2.0)
        time.sleep(processing_duration)
        
        request_counter.labels(method='POST', endpoint='/api/process', status=200).inc()
        custom_events.labels(event_type='data_processed').inc()
        
        duration = time.time() - start_time
        request_duration.labels(method='POST', endpoint='/api/process').observe(duration)
        processing_time.labels(operation='process_data').observe(processing_duration)
        
        logger.info('Data processed successfully', extra={
            'timestamp': datetime.utcnow().isoformat(),
            'duration': duration,
            'processing_duration': processing_duration,
            'status': 'success'
        })
        
        return jsonify({
            'status': 'processed',
            'processing_time': processing_duration,
            'timestamp': datetime.utcnow().isoformat()
        }), 200
        
    except Exception as e:
        logger.error('Error processing data', extra={
            'timestamp': datetime.utcnow().isoformat(),
            'error': str(e)
        })
        request_counter.labels(method='POST', endpoint='/api/process', status=500).inc()
        api_errors.labels(error_type='processing_error', endpoint='/api/process').inc()
        return jsonify({'error': str(e)}), 500
    finally:
        active_requests.dec()

@app.route('/api/simulate-error', methods=['GET'])
def simulate_error():
    """Endpoint to simulate an error for testing"""
    start_time = time.time()
    active_requests.inc()
    
    try:
        logger.warning('Simulating error', extra={
            'timestamp': datetime.utcnow().isoformat(),
            'endpoint': '/api/simulate-error'
        })
        
        # Simulate error
        raise Exception('Simulated error for observability testing')
        
    except Exception as e:
        logger.error('Simulated error occurred', extra={
            'timestamp': datetime.utcnow().isoformat(),
            'error': str(e),
            'error_type': 'simulated'
        })
        request_counter.labels(method='GET', endpoint='/api/simulate-error', status=500).inc()
        api_errors.labels(error_type='simulated_error', endpoint='/api/simulate-error').inc()
        return jsonify({'error': 'Simulated error', 'message': str(e)}), 500
    finally:
        active_requests.dec()

# ============================================================================
# ERROR HANDLERS
# ============================================================================
@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors"""
    logger.warning('404 Not Found', extra={
        'timestamp': datetime.utcnow().isoformat(),
        'path': request.path
    })
    return jsonify({'error': 'Not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors"""
    logger.error('500 Internal Server Error', extra={
        'timestamp': datetime.utcnow().isoformat(),
        'error': str(error)
    })
    return jsonify({'error': 'Internal server error'}), 500

# ============================================================================
# STARTUP
# ============================================================================
if __name__ == '__main__':
    logger.info('Starting observability app', extra={
        'timestamp': datetime.utcnow().isoformat(),
        'service': 'observability-app',
        'version': '1.0.0'
    })
    
    app.run(
        host='0.0.0.0',
        port=5000,
        debug=False,
        threaded=True
    )
