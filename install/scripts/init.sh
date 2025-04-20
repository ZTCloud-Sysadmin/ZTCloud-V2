#!/bin/bash
set -euo pipefail

# ===========================
# Load config and .env
# ===========================
ENV_FILE="/opt/ztcl/install/config/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env file at $ENV_FILE"
  exit 1
fi

export $(grep -v '^#' "$ENV_FILE" | xargs)

# ===========================
# Validate required variables
# ===========================
if [ -z "${ZTCL_NETWORK:-}" ]; then
  echo "ZTCL_NETWORK is not set in .env"
  exit 1
fi

if [ "${IS_MASTER:-false}" != "true" ]; then
  echo "Not a master node. Skipping mesh network bootstrap."
  exit 0
fi

# ===========================
# Install Tailscale
# ===========================
echo "[+] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# ===========================
# Start tailscaled service
# ===========================
echo "[+] Starting tailscaled service..."
systemctl enable --now tailscaled

# ===========================
# Create user in Headscale
# ===========================
echo "[+] Creating Headscale user '$ZTCL_NETWORK'..."
podman exec headscale headscale users create "$ZTCL_NETWORK" || true

# ===========================
# Generate Tailscale auth key
# ===========================
echo "[+] Generating Tailscale auth key..."
AUTH_KEY=$(podman exec headscale headscale preauthkeys create \
  --reusable --ephemeral --expiration 24h "$ZTCL_NETWORK" | jq -r .key)

# ===========================
# Connect to Headscale
# ===========================
echo "[+] Connecting to Headscale with auth key..."
tailscale up \
  --login-server http://localhost:8080 \
  --authkey "$AUTH_KEY" \
  --hostname "$ZTCL_NETWORK"

echo "[✔] Master node is now connected to the Headscale mesh as '$ZTCL_NETWORK'"
