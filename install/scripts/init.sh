#!/bin/bash
set -euo pipefail

# ===========================
# Load config
# ===========================
ENV_FILE="/opt/ztcl/install/config/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "[✖] Missing .env file: $ENV_FILE"
  exit 1
fi

export $(grep -v '^#' "$ENV_FILE" | xargs)

# ===========================
# Validate environment
# ===========================
echo "[*] Validating .env config..."

REQUIRED_VARS=(
  ZTCL_NETWORK
  IS_MASTER
  HEADSCALE_NAME
  HEADSCALE_SERVER_URL
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "[✖] Required variable '$var' is not set in .env"
    exit 1
  fi
done

if [ "$IS_MASTER" != "true" ]; then
  echo "[~] Skipping mesh bootstrap: this is not a master node."
  exit 0
fi

# ===========================
# Create Headscale user if needed
# ===========================
echo "[*] Checking if Headscale user '$ZTCL_NETWORK' exists..."

if podman exec "$HEADSCALE_NAME" headscale users list | grep -q "\"$ZTCL_NETWORK\""; then
  echo "[~] User '$ZTCL_NETWORK' already exists in Headscale"
else
  echo "[+] Creating user '$ZTCL_NETWORK' in Headscale..."
  podman exec "$HEADSCALE_NAME" headscale users create "$ZTCL_NETWORK"
fi

# ===========================
# Reuse or generate preauthkey
# ===========================
echo "[*] Looking for reusable preauth key..."
EXISTING_KEY=$(podman exec "$HEADSCALE_NAME" headscale preauthkeys list \
  --user "$ZTCL_NETWORK" --output json \
  | jq -r '.[] | select(.reusable == true and .expired == false) | .key' \
  | head -n 1)

if [[ -n "$EXISTING_KEY" ]]; then
  echo "[~] Found existing auth key for '$ZTCL_NETWORK'"
  AUTH_KEY="$EXISTING_KEY"
else
  echo "[+] Creating new auth key for '$ZTCL_NETWORK'..."
  AUTH_KEY=$(podman exec "$HEADSCALE_NAME" headscale preauthkeys create \
    --reusable --expiration 168h --user "$ZTCL_NETWORK" --output json \
    | jq -r .key)
fi

# ===========================
# Join Tailscale network
# ===========================
echo "[+] Running 'tailscale up' with $HEADSCALE_SERVER_URL..."
sudo tailscale up \
  --login-server "$HEADSCALE_SERVER_URL" \
  --authkey "$AUTH_KEY" \
  --hostname "$ZTCL_NETWORK"

# ===========================
# Self-test
# ===========================
echo "[*] Checking Tailscale connection..."
TAILSCALE_IP=$(tailscale ip -4 | head -n 1)

if [[ "$TAILSCALE_IP" =~ ^100\. ]]; then
  echo "[✔] Connected to Headscale mesh with IP: $TAILSCALE_IP"
else
  echo "[✖] Tailscale IP not assigned or invalid."
  exit 1
fi

echo "[✓] Master node '$ZTCL_NETWORK' successfully joined the mesh!"
