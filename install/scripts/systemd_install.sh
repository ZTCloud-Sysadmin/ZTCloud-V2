#!/bin/bash

set -euo pipefail

# Corrected path to config.sh
CONFIG_FILE="$(dirname "$0")/../config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "[!] config.sh not found at $CONFIG_FILE"
  exit 1
fi

SERVICE_NAME="ztcloud"
SYSTEMD_UNIT_FILE="/etc/systemd/system/$SERVICE_NAME.service"

echo "[*] Creating systemd service: $SERVICE_NAME"

cat <<EOF | sudo tee "$SYSTEMD_UNIT_FILE" > /dev/null
[Unit]
Description=ZTCloud Compose Stack
After=network.target

[Service]
Type=simple
User=$SYSTEM_USERNAME
WorkingDirectory=$INSTALLER_PATH/sys
ExecStart=/usr/local/bin/podman-compose -f $base_path/ztcloud-compose.yaml up
ExecStop=/usr/local/bin/podman-compose -f $base_path/ztcloud-compose.yaml down
Restart=always
Environment="PATH=/usr/local/bin:/usr/bin:/bin"

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
