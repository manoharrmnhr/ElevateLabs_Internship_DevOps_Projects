# ─────────────────────────────────────────────────────────────────
#  Multi-Stage Production Dockerfile
#  Stage 1: Build / install dependencies
#  Stage 2: Lean runtime image (no build tools)
# ─────────────────────────────────────────────────────────────────

# ── Stage 1: Builder ────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies into a prefix
COPY app/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: Runtime ────────────────────────────────────────────
FROM python:3.11-slim AS runtime

# Security: run as non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY app/ .

# Set environment defaults
ENV FLASK_ENV=production \
    PORT=5000 \
    APP_VERSION=1.0.0 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Expose application port
EXPOSE 5000

# Health check (Kubernetes also has its own, this is for Docker)
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# Switch to non-root user
USER appuser

# Run with Gunicorn WSGI server (production-grade, not Flask dev server)
CMD ["gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--workers", "2", \
     "--threads", "4", \
     "--timeout", "60", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "--log-level", "info", \
     "app:app"]
