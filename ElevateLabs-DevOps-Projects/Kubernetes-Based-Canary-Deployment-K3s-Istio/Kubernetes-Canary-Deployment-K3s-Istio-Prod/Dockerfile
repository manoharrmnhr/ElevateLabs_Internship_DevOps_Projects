# ── Stage 1: dependency install (cached layer) ───────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app
# Only copy package files first for better layer caching
COPY package*.json ./
RUN npm ci --only=production 2>/dev/null || true

# ── Stage 2: final runtime image ─────────────────────────────────────────────
FROM node:20-alpine AS runtime

# Security: run as non-root
RUN addgroup -g 1001 -S appgroup && \
    adduser  -u 1001 -S appuser -G appgroup

WORKDIR /app

# Copy app source
COPY --chown=appuser:appgroup server.js .
# Copy deps if any (none for this vanilla app)
COPY --from=deps --chown=appuser:appgroup /app/node_modules ./node_modules 2>/dev/null || true

# Set runtime env defaults (overridden by K8s env/configmap)
ENV PORT=3000 \
    APP_VERSION=v1.0.0 \
    BUILD_ID=stable-001 \
    APP_ENV=production \
    TRACK=stable \
    NODE_ENV=production

USER appuser

EXPOSE 3000

# Healthcheck for Docker/compose environments
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/healthz || exit 1

ENTRYPOINT ["node", "--max-old-space-size=128", "server.js"]
