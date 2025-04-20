#!/bin/bash

set -euo pipefail

# Load config
CONFIG_FILE="$(dirname "$0")/config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "[!] config.sh not found at $CONFIG_FILE"
  exit 1
fi

# Defaults
SYSTEMD_NAME="ztcl-stack"
SERVICE_PATH="/etc/systemd/system/${SYSTEMD_NAME}.service"
BASE_PATH="$INSTALLER_PATH"

# Copy the compose file to sys path for persistent use
SYS_COMPOSE_FILE="$INSTALLER_PATH/sys/ztcloud-compose.yaml"
INSTALL_COMPOSE_FILE="$INSTALLER_PATH/install/config/ztcloud-compose.yaml"

echo "[*] Copying ztcloud-compose.yaml to $SYS_COMPOSE_FILE"
mkdir -p "$INSTALLER_PATH/sys"
cp "$INSTALL_COMPOSE_FILE" "$SYS_COMPOSE_FILE"

# Write systemd service unit
echo "[*] Creating systemd service unit at $SERVICE_PATH"
cat <<EOF | sudo tee "$SERVICE_PATH" > /dev/null
[Unit]
Description=ZTCL Podman Compose Stack
After=network.target
Requires=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$BASE_PATH/sys
ExecStart=/usr/local/bin/podman-compose -f $BASE_PATH/sys/ztcloud-compose.yaml up -d
ExecStop=/usr/local/bin/podman-compose -f $BASE_PATH/sys/ztcloud-compose.yaml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
echo "[*] Enabling and starting $SYSTEMD_NAME service"
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now "$SYSTEMD_NAME.service"

echo "[*] Systemd service $SYSTEMD_NAME installed and started ✅"
