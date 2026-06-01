# src/Dockerfile
# ─────────────────────────────────────────────────────────────
# Multi-Stage Production Dockerfile
# Stage 1: Build — install all deps, compile
# Stage 2: Production — copy only what's needed (smaller image)
#
# Benefits of multi-stage:
# - Final image has NO dev dependencies
# - Smaller attack surface
# - Faster pulls and deploys
# ─────────────────────────────────────────────────────────────

# ── Stage 1: Builder ─────────────────────────────────────────
FROM node:18-alpine AS builder

WORKDIR /app

# Copy only package files first (layer caching — only re-runs npm install if deps changed)
COPY package*.json ./

# Install ALL dependencies (including dev, needed for build)
RUN npm ci --include=dev

# Copy source and build
COPY . .
RUN npm run build

# Remove dev dependencies after build
RUN npm prune --omit=dev

# ── Stage 2: Production ───────────────────────────────────────
FROM node:18-alpine AS production

# Security: create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -u 1001 -G appgroup

WORKDIR /app

# Copy only the built output and production node_modules
COPY --from=builder --chown=appuser:appgroup /app/dist ./dist
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/package.json ./

# Security hardening
RUN apk add --no-cache curl && \
    apk upgrade --no-cache

# Build metadata labels (good practice for traceability)
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.title="CloudDeploy App" \
      org.opencontainers.image.vendor="YourName"

# Switch to non-root user
USER appuser

# Expose app port
EXPOSE 5000

# Health check — Docker will restart container if this fails
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1

# Use exec form (not shell form) — proper signal handling for graceful shutdown
CMD ["node", "dist/server.js"]
