#!/usr/bin/env bash
# scripts/ssl-setup.sh
# ─────────────────────────────────────────────────────────────
# SSL Certificate Automation via Let's Encrypt (Certbot)
#
# Actions:
#   obtain   — get new certificate for a domain
#   renew    — renew certificate (run via cron)
#   revoke   — revoke certificate
#   status   — show cert info & expiry
#
# Usage:
#   ./scripts/ssl-setup.sh obtain yourdomain.com admin@yourdomain.com
#   ./scripts/ssl-setup.sh renew
#   ./scripts/ssl-setup.sh status yourdomain.com
# ─────────────────────────────────────────────────────────────

set -euo pipefail

ACTION="${1:-obtain}"
DOMAIN="${2:-}"
EMAIL="${3:-}"
WEBROOT_PATH="/var/www/certbot"
CERTS_PATH="/etc/letsencrypt/live"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()     { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
error()   { echo -e "${RED}❌ $1${NC}"; exit 1; }
warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }

# ── Obtain new certificate ────────────────────────────────────
obtain_cert() {
    [ -z "$DOMAIN" ] && error "Domain required: ./scripts/ssl-setup.sh obtain <domain> <email>"
    [ -z "$EMAIL"  ] && error "Email required:  ./scripts/ssl-setup.sh obtain <domain> <email>"

    log "Obtaining SSL certificate for ${DOMAIN}..."

    # Ensure webroot directory exists (Nginx must serve /.well-known/acme-challenge/)
    mkdir -p "$WEBROOT_PATH"

    # Run certbot via Docker
    docker run --rm \
        -v "$(pwd)/nginx/ssl:/etc/letsencrypt" \
        -v "${WEBROOT_PATH}:/var/www/certbot" \
        certbot/certbot certonly \
            --webroot \
            --webroot-path=/var/www/certbot \
            --email "${EMAIL}" \
            --agree-tos \
            --no-eff-email \
            --domain "${DOMAIN}" \
            --domain "www.${DOMAIN}"

    success "Certificate obtained for ${DOMAIN}"
    log "Certificate location: ${CERTS_PATH}/${DOMAIN}/"
    log "Reloading Nginx..."
    docker exec nginx_proxy nginx -s reload
    success "Nginx reloaded with new certificate"
}

# ── Renew certificates (run via cron twice daily) ─────────────
renew_certs() {
    log "Attempting certificate renewal..."

    docker run --rm \
        -v "$(pwd)/nginx/ssl:/etc/letsencrypt" \
        -v "${WEBROOT_PATH}:/var/www/certbot" \
        certbot/certbot renew \
            --webroot \
            --webroot-path=/var/www/certbot \
            --quiet

    # Reload Nginx to pick up renewed certs
    if docker ps --format '{{.Names}}' | grep -q nginx_proxy; then
        docker exec nginx_proxy nginx -s reload
        success "Nginx reloaded after renewal"
    fi

    success "Certificate renewal check complete"
}

# ── Show certificate status ────────────────────────────────────
show_status() {
    [ -z "$DOMAIN" ] && error "Domain required: ./scripts/ssl-setup.sh status <domain>"

    CERT_FILE="${CERTS_PATH}/${DOMAIN}/fullchain.pem"

    if [ ! -f "$CERT_FILE" ]; then
        # Try Docker volume path
        CERT_FILE="$(pwd)/nginx/ssl/live/${DOMAIN}/fullchain.pem"
    fi

    if [ ! -f "$CERT_FILE" ]; then
        warn "No certificate found for ${DOMAIN}"
        return 1
    fi

    log "Certificate info for ${DOMAIN}:"
    openssl x509 -in "$CERT_FILE" -noout -text | grep -E "Subject:|Issuer:|Not Before:|Not After:"

    # Days until expiry
    EXPIRY=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - $(date +%s)) / 86400 ))

    if [ "$DAYS_LEFT" -gt 30 ]; then
        success "Certificate valid for ${DAYS_LEFT} days"
    elif [ "$DAYS_LEFT" -gt 7 ]; then
        warn "Certificate expires in ${DAYS_LEFT} days — consider renewing soon"
    else
        error "Certificate expires in ${DAYS_LEFT} days — RENEW NOW"
    fi
}

# ── Install cron job for auto-renewal ─────────────────────────
install_cron() {
    SCRIPT_PATH="$(realpath "$0")"
    CRON_JOB="0 3 * * * ${SCRIPT_PATH} renew >> /var/log/certbot-renew.log 2>&1"

    # Add to crontab if not already present
    (crontab -l 2>/dev/null | grep -v "${SCRIPT_PATH}"; echo "$CRON_JOB") | crontab -
    success "Cron job installed: certificate renewal runs daily at 3am"
    log "Current crontab:"
    crontab -l
}

# ── Dispatch ──────────────────────────────────────────────────
case "$ACTION" in
    obtain)       obtain_cert ;;
    renew)        renew_certs ;;
    status)       show_status ;;
    install-cron) install_cron ;;
    *)
        echo "Usage: $0 {obtain|renew|status|install-cron} [domain] [email]"
        exit 1
        ;;
esac
