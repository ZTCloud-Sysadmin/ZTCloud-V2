#!/bin/bash
set -euo pipefail

# ===========================
# Load config + env + logging
# ===========================
source /opt/ztcl/install/scripts/load_config.sh

LOG_FILE="$LOG_DIR/ztcl-init.log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
  echo "$@"
  echo "$(date +'%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

log "========================================"
log "[+] INIT SCRIPT STARTED"
log "ZTCL_NETWORK: $ZTCL_NETWORK"
log "IS_MASTER: $IS_MASTER"
log "========================================"

# ===========================
# Validate required vars
# ===========================
REQUIRED_VARS=(
  ZTCL_NETWORK
  IS_MASTER
  HEADSCALE_NAME
  HEADSCALE_SERVER_URL
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    log "[✖] Required variable '$var' is not set in .env"
    exit 1
  fi
done

if [[ "$IS_MASTER" != "true" ]]; then
  log "[~] Skipping mesh bootstrap: not a master node"
  exit 0
fi

# ===========================
# Create Headscale user if needed
# ===========================
log "[*] Checking if Headscale user '$ZTCL_NETWORK' exists..."

if podman exec "$HEADSCALE_NAME" headscale users list | grep -q "\"$ZTCL_NETWORK\""; then
  log "[~] User '$ZTCL_NETWORK' already exists"
else
  log "[+] Creating user '$ZTCL_NETWORK'..."
  podman exec "$HEADSCALE_NAME" headscale users create "$ZTCL_NETWORK"
fi

# ===========================
# Reuse or generate preauthkey
# ===========================
log "[*] Checking for reusable preauth key..."

PREAUTH_LIST=$(podman exec "$HEADSCALE_NAME" headscale preauthkeys list \
  --user "$ZTCL_NETWORK" --output json || echo "null")

EXISTING_KEY=$(echo "$PREAUTH_LIST" \
  | jq -r 'if type=="array" then .[] | select(.reusable == true and .expired == false) | .key else empty end' \
  | head -n 1)

if [[ -n "$EXISTING_KEY" ]]; then
  log "[~] Found reusable auth key"
  AUTH_KEY="$EXISTING_KEY"
else
  log "[+] Creating new auth key for '$ZTCL_NETWORK'..."
  AUTH_KEY=$(podman exec "$HEADSCALE_NAME" headscale preauthkeys create \
    --reusable --expiration 168h --user "$ZTCL_NETWORK" --output json \
    | jq -r .key)
fi

# ===========================
# Connect to Headscale
# ===========================
log "[+] Running 'tailscale up' with $HEADSCALE_SERVER_URL..."
sudo tailscale up \
  --login-server "$HEADSCALE_SERVER_URL" \
  --authkey "$AUTH_KEY" \
  --hostname "$ZTCL_NETWORK"

# ===========================
# Self-test
# ===========================
log "[*] Verifying Tailscale connection..."
TAILSCALE_IP=$(tailscale ip -4 | head -n 1)

if [[ "$TAILSCALE_IP" =~ ^100\. ]]; then
  log "[✔] Tailscale IP assigned: $TAILSCALE_IP"
else
  log "[✖] Tailscale IP missing or invalid"
  exit 1
fi

log "[✓] Tailscale setup complete"
