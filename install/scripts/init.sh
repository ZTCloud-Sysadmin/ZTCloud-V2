#!/bin/bash
set -euo pipefail

# ===========================
# Load config
# ===========================
ENV_FILE="/opt/ztcl/install/config/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env file"
  exit 1
fi

export $(grep -v '^#' "$ENV_FILE" | xargs)

# ===========================
# Validate environment
# ===========================
if [ -z "${ZTCL_NETWORK:-}" ]; then
  echo "ZTCL_NETWORK not set in .env"
  exit 1
fi

if [ "${IS_MASTER:-false}" != "true" ]; then
  echo "[~] Skipping mesh setup (not a master)"
  exit 0
fi

# ===========================
# Create Headscale user if needed
# ===========================
if podman exec headscale headscale users list | grep -q "\"$ZTCL_NETWORK\""; then
  echo "[~] User '$ZTCL_NETWORK' already exists in Headscale"
else
  echo "[+] Creating user '$ZTCL_NETWORK' in Headscale..."
  podman exec headscale headscale users create "$ZTCL_NETWORK"
fi

# ===========================
# Reuse or generate preauthkey
# ===========================
echo "[*] Checking for reusable auth keys..."
EXISTING_KEY=$(podman exec headscale headscale preauthkeys list --user "$ZTCL_NETWORK" --output json \
  | jq -r '.[] | select(.reusable == true and .expired == false) | .key' | head -n 1)

if [[ -n "$EXISTING_KEY" ]]; then
  echo "[~] Found reusable auth key for '$ZTCL_NETWORK'"
  AUTH_KEY="$EXISTING_KEY"
else
  echo "[+] Generating new auth key for '$ZTCL_NETWORK'..."
  AUTH_KEY=$(podman exec headscale headscale preauthkeys create \
    --reusable --expiration 168h --user "$ZTCL_NETWORK" --output json | jq -r .key)
fi

# ===========================
# Join Tailscale network
# ===========================
echo "[+] Running 'tailscale up'..."
sudo tailscale up \
  --login-server http://localhost:6888 \
  --authkey "$AUTH_KEY" \
  --hostname "$ZTCL_NETWORK"

# ===========================
# Self-test
# ===========================
echo "[+] Performing self-test for Tailscale connection..."
TAILSCALE_IP=$(tailscale ip -4 | head -n 1)

if [[ "$TAILSCALE_IP" =~ ^100\. ]]; then
  echo "[✔] Connected to Headscale mesh with IP: $TAILSCALE_IP"
else
  echo "[✖] Invalid or missing Tailscale IP"
  exit 1
fi

echo "[✓] Tailscale setup completed successfully."
