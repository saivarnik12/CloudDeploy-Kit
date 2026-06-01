#!/usr/bin/env bash
# scripts/deploy.sh
# ─────────────────────────────────────────────────────────────
# Zero-Downtime Blue-Green Deployment Script
#
# Strategy:
# 1. Pull new image
# 2. Start NEW container (green) on alternate port
# 3. Run health check on green
# 4. Update Nginx to point to green
# 5. Stop OLD container (blue)
# 6. If health check fails: stop green, keep blue running
#
# Usage: ./scripts/deploy.sh [environment] [version]
# Example: ./scripts/deploy.sh production abc1234
# ─────────────────────────────────────────────────────────────

set -euo pipefail   # Exit on error, undefined var, pipe failure

# ── Arguments ────────────────────────────────────────────────
ENVIRONMENT="${1:-production}"
VERSION="${2:-latest}"
APP_NAME="clouddeploy-app"
REGISTRY="ghcr.io/yourusername/${APP_NAME}"

# ── Config ───────────────────────────────────────────────────
BLUE_PORT=5000
GREEN_PORT=5001
HEALTH_CHECK_URL="http://localhost"
MAX_RETRIES=10
RETRY_DELAY=5
LOG_FILE="/var/log/deployments.log"

# ── Colors for output ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"; }

# ── Check prerequisites ───────────────────────────────────────
check_prerequisites() {
    for cmd in docker curl; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required command not found: $cmd"
            exit 1
        fi
    done
    log "Prerequisites check passed"
}

# ── Pull new image ────────────────────────────────────────────
pull_image() {
    log "Pulling image: ${REGISTRY}/backend:${VERSION}"
    docker pull "${REGISTRY}/backend:${VERSION}" || {
        error "Failed to pull image ${VERSION}"
        exit 1
    }
    success "Image pulled successfully"
}

# ── Determine current active (blue) ──────────────────────────
get_active_container() {
    if docker ps --format '{{.Names}}' | grep -q "${APP_NAME}-blue"; then
        echo "blue"
    elif docker ps --format '{{.Names}}' | grep -q "${APP_NAME}-green"; then
        echo "green"
    else
        echo "none"
    fi
}

# ── Start new container ───────────────────────────────────────
start_new_container() {
    local color="$1"
    local port="$2"

    log "Starting ${color} container on port ${port}..."

    docker run -d \
        --name "${APP_NAME}-${color}" \
        --network app_network \
        -p "${port}:5000" \
        --env-file "/opt/app/.env.${ENVIRONMENT}" \
        --restart unless-stopped \
        --memory="512m" \
        --cpus="1.0" \
        "${REGISTRY}/backend:${VERSION}" || {
            error "Failed to start ${color} container"
            return 1
        }

    success "${color} container started on port ${port}"
}

# ── Health check ──────────────────────────────────────────────
wait_for_healthy() {
    local port="$1"
    local color="$2"
    log "Waiting for ${color} container health check (port ${port})..."

    for i in $(seq 1 $MAX_RETRIES); do
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            "http://localhost:${port}/health" 2>/dev/null || echo "000")

        if [ "$HTTP_STATUS" -eq 200 ]; then
            success "${color} container is healthy (HTTP 200)"
            return 0
        fi
        warn "Attempt ${i}/${MAX_RETRIES}: HTTP ${HTTP_STATUS}. Retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
    done

    error "${color} container failed health checks after ${MAX_RETRIES} attempts"
    return 1
}

# ── Switch Nginx to new container ─────────────────────────────
switch_traffic() {
    local new_port="$1"
    log "Switching Nginx upstream to port ${new_port}..."

    # Update Nginx upstream config dynamically
    sed -i "s/server backend:[0-9]*/server localhost:${new_port}/" \
        /etc/nginx/conf.d/upstream.conf

    nginx -t && nginx -s reload || {
        error "Nginx reload failed"
        return 1
    }
    success "Traffic switched to port ${new_port}"
}

# ── Stop old container ────────────────────────────────────────
stop_old_container() {
    local color="$1"
    local name="${APP_NAME}-${color}"
    if docker ps -q --filter name="$name" | grep -q .; then
        log "Stopping old ${color} container..."
        docker stop "$name" && docker rm "$name"
        success "Old ${color} container removed"
    fi
}

# ── Save deployment record ─────────────────────────────────────
record_deployment() {
    local status="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ${ENVIRONMENT} | ${VERSION} | ${status} | $(git rev-parse HEAD 2>/dev/null || echo 'unknown')" \
        >> "$LOG_FILE"
}

# ── Main Deploy Flow ──────────────────────────────────────────
main() {
    log "═══════════════════════════════════════════"
    log "  DEPLOYING: ${APP_NAME} v${VERSION} → ${ENVIRONMENT}"
    log "═══════════════════════════════════════════"

    check_prerequisites
    pull_image

    ACTIVE=$(get_active_container)
    log "Current active container: ${ACTIVE}"

    # Determine new color and port
    if [ "$ACTIVE" = "blue" ]; then
        NEW_COLOR="green"
        NEW_PORT=$GREEN_PORT
        OLD_COLOR="blue"
    else
        NEW_COLOR="blue"
        NEW_PORT=$BLUE_PORT
        OLD_COLOR="green"
    fi

    # Stop any existing new container (from failed previous deploy)
    stop_old_container "$NEW_COLOR" 2>/dev/null || true

    # Start new container
    if ! start_new_container "$NEW_COLOR" "$NEW_PORT"; then
        record_deployment "FAILED"
        exit 1
    fi

    # Health check new container
    if ! wait_for_healthy "$NEW_PORT" "$NEW_COLOR"; then
        warn "New container unhealthy — rolling back"
        docker stop "${APP_NAME}-${NEW_COLOR}" && docker rm "${APP_NAME}-${NEW_COLOR}"
        record_deployment "ROLLED_BACK"
        exit 1
    fi

    # Switch traffic
    if ! switch_traffic "$NEW_PORT"; then
        warn "Nginx switch failed — rolling back"
        docker stop "${APP_NAME}-${NEW_COLOR}" && docker rm "${APP_NAME}-${NEW_COLOR}"
        record_deployment "ROLLED_BACK"
        exit 1
    fi

    # Stop old container (only after traffic is switched)
    stop_old_container "$OLD_COLOR"

    record_deployment "SUCCESS"
    success "═══════════════════════════════════════════"
    success "  DEPLOYMENT COMPLETE: v${VERSION}"
    success "═══════════════════════════════════════════"
}

main "$@"
