#!/usr/bin/env bash
# monitoring/uptime-monitor.sh
# ─────────────────────────────────────────────────────────────
# Continuous Uptime Monitor
# Polls all services every CHECK_INTERVAL seconds
# Sends Slack/email alerts on failures
# Logs all results to structured JSON log
#
# Usage:
#   ./monitoring/uptime-monitor.sh                  # Run continuously
#   CHECK_INTERVAL=60 ./monitoring/uptime-monitor.sh
#   ./monitoring/uptime-monitor.sh --once           # Run once and exit
# ─────────────────────────────────────────────────────────────

set -euo pipefail

APP_URL="${APP_URL:-http://localhost}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
ALERT_WEBHOOK="${ALERT_WEBHOOK_URL:-}"
LOG_FILE="${LOG_FILE:-/var/log/uptime-monitor.log}"
CONSECUTIVE_FAILURES=0
MAX_FAILURES_BEFORE_ALERT=3   # Alert only after 3 consecutive failures (avoid flapping)
LAST_ALERT_TIME=0
ALERT_COOLDOWN=300            # 5 min between repeat alerts

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ── Logging ───────────────────────────────────────────────────
log_json() {
    local status="$1" service="$2" details="$3"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"status\":\"${status}\",\"service\":\"${service}\",\"details\":\"${details}\"}" \
        >> "$LOG_FILE"
}

# ── Check single endpoint ─────────────────────────────────────
check_endpoint() {
    local name="$1" url="$2" expected_status="${3:-200}"

    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")

    if [ "$HTTP_STATUS" -eq "$expected_status" ]; then
        echo -e "  ${GREEN}✅${NC} ${name} (HTTP ${HTTP_STATUS})"
        log_json "UP" "$name" "HTTP ${HTTP_STATUS}"
        return 0
    else
        echo -e "  ${RED}❌${NC} ${name} (HTTP ${HTTP_STATUS}, expected ${expected_status})"
        log_json "DOWN" "$name" "HTTP ${HTTP_STATUS}, expected ${expected_status}"
        return 1
    fi
}

# ── Check response content ────────────────────────────────────
check_response_content() {
    local name="$1" url="$2" pattern="$3"

    RESPONSE=$(curl -sf --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "")

    if echo "$RESPONSE" | grep -q "$pattern"; then
        echo -e "  ${GREEN}✅${NC} ${name} (content OK)"
        log_json "UP" "$name" "content check passed"
        return 0
    else
        echo -e "  ${RED}❌${NC} ${name} (content mismatch)"
        log_json "DOWN" "$name" "content check failed, pattern '${pattern}' not found"
        return 1
    fi
}

# ── Check container is running ────────────────────────────────
check_container() {
    local name="$1" container_pattern="$2"

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$container_pattern"; then
        echo -e "  ${GREEN}✅${NC} Container: ${name}"
        log_json "UP" "container:${name}" "running"
        return 0
    else
        echo -e "  ${RED}❌${NC} Container: ${name} (not running)"
        log_json "DOWN" "container:${name}" "not running"
        return 1
    fi
}

# ── Send Slack alert ──────────────────────────────────────────
send_alert() {
    local message="$1" severity="${2:-warning}"

    local NOW
    NOW=$(date +%s)

    # Respect cooldown
    if [ $((NOW - LAST_ALERT_TIME)) -lt $ALERT_COOLDOWN ]; then
        return 0
    fi
    LAST_ALERT_TIME=$NOW

    local emoji="⚠️"
    [ "$severity" = "critical" ] && emoji="🔴"
    [ "$severity" = "recovery" ] && emoji="✅"

    echo -e "${YELLOW}Sending alert: ${message}${NC}"

    # Slack webhook
    if [ -n "$ALERT_WEBHOOK" ]; then
        curl -sf -X POST "$ALERT_WEBHOOK" \
            -H 'Content-type: application/json' \
            --data "{\"text\":\"${emoji} *CloudDeploy Monitor* [$(date '+%Y-%m-%d %H:%M:%S')]\n${message}\"}" \
            >/dev/null 2>&1 || true
    fi

    # Also log to file
    log_json "ALERT" "monitor" "$message"
}

# ── Run all checks ────────────────────────────────────────────
run_checks() {
    local FAILURES=0

    echo -e "\n${BLUE}═══════════════════════════════════${NC}"
    echo -e "${BLUE}  Uptime Check — $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BLUE}═══════════════════════════════════${NC}"

    # API checks
    echo "  [API]"
    check_endpoint "Health endpoint" "${APP_URL}/health"                    || ((FAILURES++))
    check_response_content "Health content" "${APP_URL}/health" "healthy"   || ((FAILURES++))
    check_endpoint "Readiness probe" "${APP_URL}/health/ready"              || ((FAILURES++))

    # Container checks
    echo "  [Containers]"
    check_container "nginx"    "nginx"    || ((FAILURES++))
    check_container "backend"  "backend"  || ((FAILURES++))
    check_container "postgres" "postgres" || ((FAILURES++))
    check_container "redis"    "redis"    || ((FAILURES++))

    # SSL check
    echo "  [SSL]"
    DOMAIN_HOST="${APP_URL#https://}"
    DOMAIN_HOST="${DOMAIN_HOST#http://}"
    if echo | openssl s_client -connect "${DOMAIN_HOST}:443" -servername "${DOMAIN_HOST}" 2>/dev/null \
        | openssl x509 -noout -checkend $((7 * 86400)) 2>/dev/null; then
        echo -e "  ${GREEN}✅${NC} SSL certificate valid (7+ days)"
    else
        echo -e "  ${YELLOW}⚠️ ${NC} SSL certificate expires within 7 days!"
        ((FAILURES++))
    fi

    return $FAILURES
}

# ── Main loop ─────────────────────────────────────────────────
main() {
    echo "CloudDeploy Uptime Monitor started"
    echo "  APP_URL:        ${APP_URL}"
    echo "  CHECK_INTERVAL: ${CHECK_INTERVAL}s"
    echo "  LOG_FILE:       ${LOG_FILE}"

    if [ "${1:-}" = "--once" ]; then
        run_checks
        exit $?
    fi

    while true; do
        FAILURE_COUNT=0
        run_checks || FAILURE_COUNT=$?

        if [ "$FAILURE_COUNT" -gt 0 ]; then
            ((CONSECUTIVE_FAILURES++))
            echo -e "\n${RED}${FAILURE_COUNT} check(s) failed. Consecutive failures: ${CONSECUTIVE_FAILURES}${NC}"

            if [ "$CONSECUTIVE_FAILURES" -ge "$MAX_FAILURES_BEFORE_ALERT" ]; then
                send_alert "${FAILURE_COUNT} health checks failing on ${APP_URL} (${CONSECUTIVE_FAILURES} consecutive)" "critical"
            fi
        else
            if [ "$CONSECUTIVE_FAILURES" -ge "$MAX_FAILURES_BEFORE_ALERT" ]; then
                send_alert "All checks recovered on ${APP_URL}" "recovery"
            fi
            CONSECUTIVE_FAILURES=0
            echo -e "\n${GREEN}All checks passed.${NC}"
        fi

        sleep "$CHECK_INTERVAL"
    done
}

main "$@"
