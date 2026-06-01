#!/usr/bin/env bash
# scripts/rollback.sh
# ─────────────────────────────────────────────────────────────
# Emergency Rollback Script
# Restores the previous known-good image version
# Usage: ./scripts/rollback.sh [environment]
# ─────────────────────────────────────────────────────────────

set -euo pipefail

ENVIRONMENT="${1:-production}"
APP_NAME="clouddeploy-app"
REGISTRY="ghcr.io/yourusername/${APP_NAME}"
LOG_FILE="/var/log/deployments.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"; }

# ── Find previous successful deployment version ────────────────
get_previous_version() {
    # Read deployment log, find last 2 SUCCESS entries, return the older one
    PREV_VERSION=$(grep "SUCCESS" "$LOG_FILE" | tail -2 | head -1 | awk -F'|' '{print $3}' | tr -d ' ')

    if [ -z "$PREV_VERSION" ]; then
        error "No previous successful deployment found in log"
        exit 1
    fi
    echo "$PREV_VERSION"
}

# ── Confirm rollback ──────────────────────────────────────────
confirm_rollback() {
    local prev="$1"
    echo -e "${YELLOW}⚠️  ROLLBACK REQUESTED${NC}"
    echo "    Environment : ${ENVIRONMENT}"
    echo "    Rolling back to: ${prev}"
    read -rp "Confirm rollback? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log "Rollback cancelled by user"
        exit 0
    fi
}

main() {
    log "═══════════════════════════════════════"
    log "  ROLLBACK INITIATED — ${ENVIRONMENT}"
    log "═══════════════════════════════════════"

    PREV_VERSION=$(get_previous_version)
    log "Previous good version: ${PREV_VERSION}"

    # Skip confirmation if running in CI (non-interactive)
    if [ -t 0 ]; then
        confirm_rollback "$PREV_VERSION"
    fi

    # Re-run deploy with previous version
    log "Re-deploying version ${PREV_VERSION}..."
    bash "$(dirname "$0")/deploy.sh" "$ENVIRONMENT" "$PREV_VERSION"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | ${ENVIRONMENT} | ${PREV_VERSION} | ROLLBACK_SUCCESS" >> "$LOG_FILE"
    success "Rollback to ${PREV_VERSION} complete"
}

main "$@"
