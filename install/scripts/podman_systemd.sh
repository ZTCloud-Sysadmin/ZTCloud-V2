#!/bin/bash

set -euo pipefail

# Load config from .env
source /opt/ztcl/sys/config/load_config.sh

SERVICE_NAME="ztcloud"
SYSTEMD_UNIT_FILE="/etc/systemd/system/$SERVICE_NAME.service"
PODMAN_COMPOSE_PATH="/home/$SYSTEM_USERNAME/.local/bin/podman-compose"
COMPOSE_FILE="$DATA_PATH/ztcloud-compose.yaml"
WORKING_DIR="$DATA_PATH"

# Check podman-compose exists
if [[ ! -x "$PODMAN_COMPOSE_PATH" ]]; then
  echo "[!] podman-compose not found at $PODMAN_COMPOSE_PATH"
  exit 1
fi

# Ensure .env is available next to the compose file (for podman-compose)
echo "[*] Linking .env for podman-compose compatibility..."
ln -sf /opt/ztcl/sys/config/.env /opt/ztcl/sys/.env

echo "[*] Creating systemd service: $SERVICE_NAME"

cat <<EOF | sudo tee "$SYSTEMD_UNIT_FILE" > /dev/null
[Unit]
Description=ZTCloud Compose Stack
After=network-online.target podman.socket
Wants=network-online.target

[Service]
Type=simple
User=$SYSTEM_USERNAME
WorkingDirectory=$WORKING_DIR
ExecStart=/bin/bash -lc "sleep 30 && $PODMAN_COMPOSE_PATH -f $COMPOSE_FILE up"
ExecStop=/bin/bash -lc "$PODMAN_COMPOSE_PATH -f $COMPOSE_FILE down"
Restart=always
Environment="PATH=/home/$SYSTEM_USERNAME/.local/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

echo "[*] Reloading systemd daemon..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

echo "[*] Enabling and starting $SERVICE_NAME.service..."
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

echo "[OK] systemd service installed and running ✅"
