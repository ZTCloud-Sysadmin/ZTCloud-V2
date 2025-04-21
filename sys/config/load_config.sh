#!/bin/bash

# ===========================
# Shared Config Loader
# ===========================

# Canonical path to .env
export ENV_FILE="/opt/ztcl/sys/config/.env"

if [[ -f "$ENV_FILE" ]]; then
  echo "[*] Loading environment from $ENV_FILE"
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
else
  echo "[!] ENV file not found at $ENV_FILE"
  exit 1
fi

# Derived paths (set once globally for all scripts)
export LOG_DIR="$DATA_PATH/logs"
export COMPOSE_FILE="$DATA_PATH/ztcloud-compose.yaml"
