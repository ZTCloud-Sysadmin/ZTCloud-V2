#!/bin/bash
set -euo pipefail

# ===========================
# Load config
# ===========================
CONFIG_FILE="/opt/ztcl/sys/config/config.sh"
ENV_FILE="/opt/ztcl/sys/config/.env"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

if [[ -f "$ENV_FILE" ]]; then
  set -o allexport; source "$ENV_FILE"; set +o allexport
fi

# ===========================
# Logging setup
# ===========================
LOG_FILE="$INSTALLER_PATH/logs/ztcl-firewall.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"; chmod 600 "$LOG_FILE"

log() {
  echo "$@"
  echo "$(date +'%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

log "========================================"
log "[+] firewall.sh STARTED"
log "IS_MASTER: ${IS_MASTER:-undefined}"
log "========================================"

# ===========================
# Check UFW availability
# ===========================
if ! command -v ufw &>/dev/null; then
  log "[!] ufw not found. Please install it using: apt install ufw"
  exit 1
fi

# ===========================
# Apply UFW rules (only on master)
# ===========================
if [[ "${IS_MASTER:-false}" != "true" ]]; then
  log "[~] Not a master node — skipping firewall config."
  exit 0
fi

log "[*] Applying UFW firewall rules from .env..."

ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp
log "[+] UFW allow: SSH (22/tcp)"

ufw allow "${HEADSCALE_HTTP_PORT:-6888}"/tcp
log "[+] UFW allow: Headscale (${HEADSCALE_HTTP_PORT}/tcp)"

ufw allow "${HEADSCALE_STUN_PORT:-3478}"/udp
log "[+] UFW allow: STUN (${HEADSCALE_STUN_PORT}/udp)"

ufw allow "${DERP_PORT:-443}"/tcp
log "[+] UFW allow: DERP (${DERP_PORT}/tcp)"

ufw allow "${COREDNS_TCP_PORT:-53}"/tcp
log "[+] UFW allow: DNS TCP (${COREDNS_TCP_PORT}/tcp)"

ufw allow "${COREDNS_UDP_PORT:-53}"/udp
log "[+] UFW allow: DNS UDP (${COREDNS_UDP_PORT}/udp)"

log "[*] Enabling UFW firewall..."
ufw --force enable

log "[✓] UFW configuration applied successfully."
