#!/usr/bin/env bash
# scripts/setup-server.sh
# ─────────────────────────────────────────────────────────────
# One-Time Server Bootstrap Script
# Run once on a fresh Ubuntu 22.04 / 24.04 VPS
#
# Installs: Docker, Docker Compose, Git, UFW firewall rules
# Creates deploy user, sets up directory structure
#
# Usage: sudo bash scripts/setup-server.sh
# ─────────────────────────────────────────────────────────────

set -euo pipefail

DEPLOY_USER="deploy"
APP_DIR="/opt/app"
LOG_DIR="/var/log/clouddeploy"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${BLUE}[SETUP]${NC} $1"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }

# ── Ensure running as root ────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo bash scripts/setup-server.sh"
    exit 1
fi

log "Starting server bootstrap..."

# ── System update ─────────────────────────────────────────────
log "Updating system packages..."
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git unzip \
    ca-certificates gnupg lsb-release \
    ufw fail2ban

success "System packages updated"

# ── Install Docker ────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    success "Docker installed"
else
    success "Docker already installed: $(docker --version)"
fi

# ── Create deploy user ────────────────────────────────────────
if ! id "$DEPLOY_USER" &>/dev/null; then
    log "Creating deploy user: ${DEPLOY_USER}..."
    useradd -m -s /bin/bash "$DEPLOY_USER"
    usermod -aG docker "$DEPLOY_USER"
    # Allow deploy user to run deploy scripts without password
    echo "${DEPLOY_USER} ALL=(ALL) NOPASSWD: /opt/app/scripts/deploy.sh, /opt/app/scripts/rollback.sh" \
        >> /etc/sudoers.d/deploy
    success "Deploy user created"
else
    success "Deploy user already exists"
fi

# ── Directory structure ────────────────────────────────────────
log "Setting up directory structure..."
mkdir -p "$APP_DIR" "$LOG_DIR" /var/www/certbot
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$APP_DIR"
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$LOG_DIR"
success "Directories created"

# ── Firewall (UFW) ────────────────────────────────────────────
log "Configuring UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw --force enable
success "Firewall configured (SSH, HTTP, HTTPS allowed)"

# ── Fail2ban (brute-force protection) ─────────────────────────
log "Configuring fail2ban..."
systemctl enable fail2ban
systemctl start fail2ban
success "fail2ban enabled"

# ── Docker log rotation ───────────────────────────────────────
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl reload docker
success "Docker log rotation configured"

# ── System log rotation ───────────────────────────────────────
cat > /etc/logrotate.d/clouddeploy <<EOF
${LOG_DIR}/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
}
EOF
success "Log rotation configured"

# ── SSH hardening ─────────────────────────────────────────────
log "Hardening SSH..."
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl reload sshd
success "SSH password auth disabled, root login disabled"

echo ""
success "═══════════════════════════════════════════════"
success "  Server bootstrap complete!"
success "═══════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Copy your SSH public key to: /home/${DEPLOY_USER}/.ssh/authorized_keys"
echo "  2. Clone repo to: ${APP_DIR}"
echo "  3. Copy .env.production to: ${APP_DIR}/.env"
echo "  4. Run: ./scripts/ssl-setup.sh obtain <domain> <email>"
echo "  5. Run: ./scripts/deploy.sh production v1.0.0"
