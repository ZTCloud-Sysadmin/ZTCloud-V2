#!/bin/bash
set -euo pipefail

# ===========================
# Define default path
# ===========================
DEFAULT_INSTALLER_PATH="/opt/ztcl"
CONFIG_DIR="$DEFAULT_INSTALLER_PATH/sys/config"

# ===========================
# Load config.sh (INSTALLER_PATH, SYSTEM_USERNAME, etc.)
# ===========================
CONFIG_FILE="$CONFIG_DIR/config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "[✖] Missing config.sh at $CONFIG_FILE"
  exit 1
fi

# ===========================
# Load .env (ports, flags, etc.)
# ===========================
ENV_FILE="$CONFIG_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
else
  echo "[✖] Missing .env at $ENV_FILE"
  exit 1
fi

# ===========================
# Ensure log directory exists
# ===========================
LOG_DIR="$INSTALLER_PATH/logs"
mkdir -p "$LOG_DIR"
