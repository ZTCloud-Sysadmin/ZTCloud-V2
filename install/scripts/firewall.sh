#!/bin/bash
set -euo pipefail

# ===========================
# Load config + .env + log path
# ===========================
source /opt/ztcl/install/scripts/load_config.sh

LOG_FILE="$LOG_DIR/ztcl-firewall.log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
  echo "$@"
  echo "$(date +'%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

log "========================================"
log "[+] firewall.sh STARTED"
log "IS_MASTER: ${IS_MASTER:-}"
log "========================================"

# ===========================
# Only apply on master node
# ===========================
if [[ "${IS_MASTER:-false}" != "true" ]]; then
  log "[~] Not a master node — skipping UFW configuration."
  exit 0
fi

# ===========================
# Apply dynamic UFW rules
# ===========================
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
