#!/bin/bash
set -euo pipefail

# ===========================
# Load config, .env, and log setup
# ===========================
source /opt/ztcl/install/scripts/load_config.sh

LOG_FILE="$LOG_DIR/ztcl-systemd.log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
  echo "$@"
  echo "$(date +'%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

log "========================================"
log "[+] systemd_install.sh STARTED"
log "INSTALLER_PATH: $INSTALLER_PATH"
log "SYSTEM_USERNAME: $SYSTEM_USERNAME"
log "========================================"

# ===========================
# Define service paths
# ===========================
SERVICE_NAME="ztcloud"
SYSTEMD_UNIT_FILE="/etc/systemd/system/$SERVICE_NAME.service"
PODMAN_COMPOSE_PATH="/home/$SYSTEM_USERNAME/.local/bin/podman-compose"
WORKING_DIR="$INSTALLER_PATH/sys"
COMPOSE_FILE="$WORKING_DIR/ztcloud-compose.yaml"

# ===========================
# Sanity check
# ===========================
if [[ ! -x "$PODMAN_COMPOSE_PATH" ]]; then
  log "[!] podman-compose not found at $PODMAN_COMPOSE_PATH"
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  log "[!] Compose file missing: $COMPOSE_FILE"
  exit 1
fi

# ===========================
# Write systemd unit
# ===========================
log "[*] Creating systemd service: $SERVICE_NAME"

cat <<EOF | sudo tee "$SYSTEMD_UNIT_FILE" > /dev/null
[Unit]
Description=ZTCloud Compose Stack
After=network.target

[Service]
Type=simple
User=$SYSTEM_USERNAME
WorkingDirectory=$WORKING_DIR
ExecStart=/bin/bash -lc "sleep 20 && $PODMAN_COMPOSE_PATH -f $COMPOSE_FILE up"
ExecStop=/bin/bash -lc "$PODMAN_COMPOSE_PATH -f $COMPOSE_FILE down"
Restart=always
Environment="PATH=/home/$SYSTEM_USERNAME/.local/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

# ===========================
# Reload + enable systemd service
# ===========================
log "[*] Reloading systemd daemon..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

log "[*] Enabling and starting $SERVICE_NAME.service..."
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

log "[✓] systemd service installed and running"
