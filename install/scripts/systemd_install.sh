#!/bin/bash

set -euo pipefail

# Load config variables
CONFIG_FILE="$(dirname "$0")/../config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "[!] config.sh not found at $CONFIG_FILE"
  exit 1
fi

SERVICE_NAME="ztcloud"
SYSTEMD_UNIT_FILE="/etc/systemd/system/$SERVICE_NAME.service"

# Determine full path to podman-compose
PODMAN_COMPOSE_PATH="$HOME/.local/bin/podman-compose"

if [[ ! -x "$PODMAN_COMPOSE_PATH" ]]; then
  echo "[!] podman-compose not found at $PODMAN_COMPOSE_PATH"
  exit 1
fi

# Resolve working directory
WORKING_DIR="$INSTALLER_PATH/sys"
COMPOSE_FILE="$WORKING_DIR/ztcloud-compose.yaml"

echo "[*] Creating systemd service: $SERVICE_NAME"

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
Environment="PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
echo "[*] Reloading systemd daemon..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

echo "[*] Enabling and starting $SERVICE_NAME.service..."
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

echo "[OK] systemd service installed and running ✅"
