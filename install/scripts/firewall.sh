#!/bin/bash
set -euo pipefail

# ===========================
# Load config + env + logging
# ===========================
CONFIG_FILE="/opt/ztcl/sys/config/config.sh"
ENV_FILE="/opt/ztcl/sys/config/.env"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "[!] Missing config.sh"
  exit 1
fi

if [[ -f "$ENV_FILE" ]]; then
  set -o allexport; source "$ENV_FILE"; set +o allexport
else
  echo "[!] Missing .env"
  exit 1
fi

LOG_FILE="$INSTALLER_PATH/logs/ztcl-firewall.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"; chmod 600 "$LOG_FILE"

log() {
  echo "$@"
  echo "$(date +'%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

log "========================================"
log "[+] firewall.sh STARTED"
log "IS_MASTER: $IS_MASTER"
log "========================================"

if [[ "${IS_MASTER:-false}" != "true" ]]; then
  log "[~] Not a master node — skipping UFW configuration."
  exit 0
fi

# ===========================
# Run permission + path check
# ===========================
PERM_CHECK="$INSTALLER_PATH/install/scripts/permission_check.sh"
if [[ -f "$PERM_CHECK" ]]; then
  source "$PERM_CHECK"
  fix_ownership_if_needed "$INSTALLER_PATH" "$SYSTEM_USERNAME"
  ensure_user_path
fi

# ===========================
# Apply UFW rules
# ===========================
log "[*] Applying UFW firewall rules from .env..."

sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow 22/tcp
log "[+] UFW allow: SSH (22/tcp)"

sudo ufw allow "${HEADSCALE_HTTP_PORT:-6888}"/tcp
log "[+] UFW allow: Headscale (${HEADSCALE_HTTP_PORT}/tcp)"

sudo ufw allow "${HEADSCALE_STUN_PORT:-3478}"/udp
log "[+] UFW allow: STUN (${HEADSCALE_STUN_PORT}/udp)"

sudo ufw allow "${DERP_PORT:-443}"/tcp
log "[+] UFW allow: DERP (${DERP_PORT}/tcp)"

sudo ufw allow "${COREDNS_TCP_PORT:-53}"/tcp
log "[+] UFW allow: DNS TCP (${COREDNS_TCP_PORT}/tcp)"

sudo ufw allow "${COREDNS_UDP_PORT:-53}"/udp
log "[+] UFW allow: DNS UDP (${COREDNS_UDP_PORT}/udp)"

log "[*] Enabling UFW firewall..."
sudo ufw --force enable

log "[✓] UFW configuration applied successfully."
