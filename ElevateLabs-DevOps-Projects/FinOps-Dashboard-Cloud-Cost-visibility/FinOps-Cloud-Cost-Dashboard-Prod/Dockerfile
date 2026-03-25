# ──────────────────────────────────────────────────────────────────
# FinOps Dashboard — Production Dockerfile
# Base: Python 3.11 slim
# ──────────────────────────────────────────────────────────────────
FROM python:3.11-slim

# Metadata
LABEL maintainer="finops-team"
LABEL description="FinOps Cloud Free Tier Usage Tracker Pipeline"
LABEL version="1.0.0"

# Prevent Python bytecode writes and enable unbuffered output
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    FINOPS_DB_PATH=/app/data/finops.db \
    LOG_LEVEL=INFO

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY src/       ./src/
COPY scripts/   ./scripts/

# Create runtime directories
RUN mkdir -p data reports logs

# Non-root user for security
RUN groupadd -r finops && useradd -r -g finops finops \
    && chown -R finops:finops /app
USER finops

# Health check
HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
    CMD python -c "from src import db; s=db.get_db_stats(); print('OK:', s)" || exit 1

# Default: run the fetch pipeline in simulate mode
CMD ["python", "-m", "scripts.run_fetch", "--mode", "simulate", "--days", "30"]
