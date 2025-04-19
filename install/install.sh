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

# Check if current user matches SYSTEM_USERNAME
CURRENT_USER="$(whoami)"
if [[ "$CURRENT_USER" != "$SYSTEM_USERNAME" ]]; then
  echo "[*] install.sh must be run as $SYSTEM_USERNAME. Current user: $CURRENT_USER"
  echo "[*] Re-executing as correct user..."
  exec sudo -u "$SYSTEM_USERNAME" bash "$0"
fi

# All good, continue
echo "========================================"
echo "[+] INSTALLER PIPELINE OK"
echo "[+] Reached install.sh"
echo "----------------------------------------"
echo "INSTALLER_PATH: $INSTALLER_PATH"
echo "SYSTEM_USERNAME: $SYSTEM_USERNAME"
echo "ZTCL_VERSION: $ZTCL_VERSION"
echo "========================================"
