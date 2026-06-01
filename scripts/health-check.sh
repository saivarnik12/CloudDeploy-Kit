#!/usr/bin/env bash
# scripts/health-check.sh
# ─────────────────────────────────────────────────────────────
# Service Health Verification Script
# Checks: API, Database, Redis, Nginx, Disk Space, Memory
# Exit code 0 = all healthy, 1 = one or more failures
# ─────────────────────────────────────────────────────────────

set -euo pipefail

APP_URL="${APP_URL:-http://localhost}"
PASS=0
FAIL=0
WARN=0

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

check() {
    local name="$1"; local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}✅ PASS${NC} — ${name}"
        ((PASS++))
    else
        echo -e "${RED}❌ FAIL${NC} — ${name}"
        ((FAIL++))
    fi
}

warn_check() {
    local name="$1"; local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}✅ PASS${NC} — ${name}"
        ((PASS++))
    else
        echo -e "${YELLOW}⚠️  WARN${NC} — ${name}"
        ((WARN++))
    fi
}

echo "═══════════════════════════════════"
echo "  Health Check — $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════"

# API health endpoint
check "API /health endpoint" "curl -sf ${APP_URL}/health | grep -q 'healthy'"

# Database connectivity
check "PostgreSQL running" "docker ps | grep -q postgres"
check "PostgreSQL accepting connections" "docker exec \$(docker ps -q -f name=postgres) pg_isready -U postgres"

# Redis
check "Redis running" "docker ps | grep -q redis"
check "Redis responding" "docker exec \$(docker ps -q -f name=redis) redis-cli ping | grep -q PONG"

# Nginx
check "Nginx running" "docker ps | grep -q nginx"
check "Nginx config valid" "docker exec \$(docker ps -q -f name=nginx) nginx -t"

# Disk space (warn if > 80% used)
DISK_USED=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USED" -lt 80 ]; then
    echo -e "${GREEN}✅ PASS${NC} — Disk space: ${DISK_USED}% used"
    ((PASS++))
elif [ "$DISK_USED" -lt 90 ]; then
    echo -e "${YELLOW}⚠️  WARN${NC} — Disk space: ${DISK_USED}% used (approaching limit)"
    ((WARN++))
else
    echo -e "${RED}❌ FAIL${NC} — Disk space CRITICAL: ${DISK_USED}% used"
    ((FAIL++))
fi

# Memory (warn if > 85% used)
MEM_USED=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
if [ "$MEM_USED" -lt 85 ]; then
    echo -e "${GREEN}✅ PASS${NC} — Memory: ${MEM_USED}% used"
    ((PASS++))
else
    echo -e "${YELLOW}⚠️  WARN${NC} — Memory: ${MEM_USED}% used"
    ((WARN++))
fi

# SSL certificate expiry (warn if < 30 days)
warn_check "SSL certificate valid (30+ days)" \
    "echo | openssl s_client -connect ${APP_URL#https://}:443 2>/dev/null | openssl x509 -noout -checkend $((30*86400))"

echo "═══════════════════════════════════"
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${YELLOW}${WARN} warnings${NC}, ${RED}${FAIL} failed${NC}"
echo "═══════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
