"""
Test Suite — CI/CD Pipeline Flask Application
Covers: unit tests, route validation, error handling, edge cases
"""

import json
import pytest
from app.app import create_app


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def app():
    """Create test application instance."""
    application = create_app("testing")
    application.config["TESTING"] = True
    return application


@pytest.fixture(scope="module")
def client(app):
    """Test client for the Flask application."""
    return app.test_client()


# ── Home Endpoint ─────────────────────────────────────────────────────────────

class TestHomeEndpoint:
    def test_home_returns_200(self, client):
        response = client.get("/")
        assert response.status_code == 200

    def test_home_content_type_json(self, client):
        response = client.get("/")
        assert response.content_type == "application/json"

    def test_home_has_status_field(self, client):
        data = client.get("/").get_json()
        assert "status" in data
        assert data["status"] == "running"

    def test_home_has_version_field(self, client):
        data = client.get("/").get_json()
        assert "version" in data

    def test_home_has_timestamp(self, client):
        data = client.get("/").get_json()
        assert "timestamp" in data
        assert data["timestamp"].endswith("Z")

    def test_home_has_app_name(self, client):
        data = client.get("/").get_json()
        assert "app" in data
        assert data["app"] == "CI/CD Pipeline Demo"


# ── Health Endpoint ───────────────────────────────────────────────────────────

class TestHealthEndpoint:
    def test_health_returns_200(self, client):
        response = client.get("/health")
        assert response.status_code == 200

    def test_health_status_healthy(self, client):
        data = client.get("/health").get_json()
        assert data["status"] == "healthy"

    def test_health_is_json(self, client):
        response = client.get("/health")
        assert response.content_type == "application/json"


# ── Readiness Endpoint ────────────────────────────────────────────────────────

class TestReadyEndpoint:
    def test_ready_returns_200(self, client):
        response = client.get("/ready")
        assert response.status_code == 200

    def test_ready_status_field(self, client):
        data = client.get("/ready").get_json()
        assert data["status"] == "ready"


# ── Metrics Endpoint ──────────────────────────────────────────────────────────

class TestMetricsEndpoint:
    def test_metrics_returns_200(self, client):
        response = client.get("/metrics")
        assert response.status_code == 200

    def test_metrics_has_uptime(self, client):
        data = client.get("/metrics").get_json()
        assert "uptime_seconds" in data
        assert isinstance(data["uptime_seconds"], float)

    def test_metrics_has_version(self, client):
        data = client.get("/metrics").get_json()
        assert "version" in data


# ── Echo Endpoint ─────────────────────────────────────────────────────────────

class TestEchoEndpoint:
    def test_echo_returns_payload(self, client):
        payload = {"hello": "world", "number": 42}
        response = client.post(
            "/echo",
            data=json.dumps(payload),
            content_type="application/json",
        )
        assert response.status_code == 200
        data = response.get_json()
        assert data["echo"] == payload

    def test_echo_invalid_json_returns_400(self, client):
        response = client.post(
            "/echo",
            data="not-json",
            content_type="application/json",
        )
        assert response.status_code == 400

    def test_echo_nested_payload(self, client):
        payload = {"nested": {"key": "value"}, "list": [1, 2, 3]}
        response = client.post(
            "/echo",
            data=json.dumps(payload),
            content_type="application/json",
        )
        assert response.status_code == 200
        assert response.get_json()["echo"] == payload


# ── Error Handling ────────────────────────────────────────────────────────────

class TestErrorHandling:
    def test_404_returns_json(self, client):
        response = client.get("/nonexistent-route")
        assert response.status_code == 404
        data = response.get_json()
        assert "error" in data
        assert data["code"] == 404

    def test_405_method_not_allowed(self, client):
        response = client.delete("/health")
        assert response.status_code == 405
