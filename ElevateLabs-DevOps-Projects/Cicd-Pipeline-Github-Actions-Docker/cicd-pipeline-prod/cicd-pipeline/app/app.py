"""
Production-Grade Flask Application
CI/CD Pipeline Demo — GitHub Actions + Docker + Minikube
"""

import os
import time
import logging
from datetime import datetime
from flask import Flask, jsonify, request

# ── Logging Configuration ─────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

# ── App Factory ───────────────────────────────────────────────────────────────
def create_app(config_name: str = "production") -> Flask:
    app = Flask(__name__)

    # Configuration
    app.config.update(
        ENV=config_name,
        APP_VERSION=os.getenv("APP_VERSION", "1.0.0"),
        START_TIME=time.time(),
    )

    # ── Routes ────────────────────────────────────────────────────────────────

    @app.route("/", methods=["GET"])
    def home():
        """Root endpoint — returns app info."""
        return jsonify({
            "app": "CI/CD Pipeline Demo",
            "version": app.config["APP_VERSION"],
            "status": "running",
            "environment": app.config["ENV"],
            "timestamp": datetime.utcnow().isoformat() + "Z",
        }), 200

    @app.route("/health", methods=["GET"])
    def health():
        """Kubernetes liveness probe endpoint."""
        return jsonify({"status": "healthy"}), 200

    @app.route("/ready", methods=["GET"])
    def ready():
        """Kubernetes readiness probe endpoint."""
        return jsonify({"status": "ready"}), 200

    @app.route("/metrics", methods=["GET"])
    def metrics():
        """Basic uptime metrics endpoint."""
        uptime = round(time.time() - app.config["START_TIME"], 2)
        return jsonify({
            "uptime_seconds": uptime,
            "version": app.config["APP_VERSION"],
            "environment": app.config["ENV"],
        }), 200

    @app.route("/echo", methods=["POST"])
    def echo():
        """Echo endpoint — returns JSON payload back."""
        payload = request.get_json(silent=True)
        if payload is None:
            return jsonify({"error": "Invalid JSON payload"}), 400
        return jsonify({"echo": payload}), 200

    @app.errorhandler(404)
    def not_found(e):
        return jsonify({"error": "Route not found", "code": 404}), 404

    @app.errorhandler(405)
    def method_not_allowed(e):
        return jsonify({"error": "Method not allowed", "code": 405}), 405

    logger.info("Flask app created — version=%s env=%s",
                app.config["APP_VERSION"], config_name)
    return app


# ── Entry Point ───────────────────────────────────────────────────────────────
app = create_app(os.getenv("FLASK_ENV", "production"))

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    debug = os.getenv("FLASK_ENV") == "development"
    logger.info("Starting server on port %d (debug=%s)", port, debug)
    app.run(host="0.0.0.0", port=port, debug=debug)
