# ── Stage 1: dependency install ──────────────────────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production 2>/dev/null || true

# ── Stage 2: final runtime image ─────────────────────────────────────────────
FROM node:20-alpine AS runtime

RUN addgroup -g 1001 -S appgroup && \
    adduser  -u 1001 -S appuser -G appgroup

WORKDIR /app

COPY --chown=appuser:appgroup server.js .
COPY --from=deps --chown=appuser:appgroup /app/node_modules ./node_modules 2>/dev/null || true

ENV PORT=3000 \
    APP_VERSION=v2.0.0 \
    BUILD_ID=canary-001 \
    APP_ENV=production \
    TRACK=canary \
    FAULT_RATE=0.03 \
    NODE_ENV=production

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/healthz || exit 1

ENTRYPOINT ["node", "--max-old-space-size=128", "server.js"]
