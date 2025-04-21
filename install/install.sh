#!/bin/bash

set -euo pipefail

# Ensure PATH includes pipx-installed binaries
export PATH="$PATH:/usr/local/bin:/root/.local/bin"

# ===========================
# Load .env and derived config
# ===========================
source /opt/ztcl/sys/config/load_config.sh

# ===========================
# Validate required environment variables from .env
# ===========================
echo "[*] Validating .env environment variables..."

REQUIRED_ENV_VARS=(
  DATA_PATH HEADSCALE_IMAGE HEADSCALE_NAME HEADSCALE_HTTP_PORT HEADSCALE_STUN_PORT
  ETCD_IMAGE ETCD_NAME ETCD_CLIENT_PORT ETCD_NODE_NAME ETCD_CLUSTER_TOKEN
  COREDNS_IMAGE COREDNS_NAME COREDNS_TCP_PORT COREDNS_UDP_PORT
  CADDY_IMAGE CADDY_NAME CADDY_ADMIN_PORT CADDY_HTTPS_PORT
  ZTCLP_IMAGE ZTCLP_NAME ZTCLP_ADMIN_PORT
  TLS_EMAIL BASE_DOMAIN
)

missing=0
for var in "${REQUIRED_ENV_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "[FAIL] Missing required .env variable: $var"
    missing=1
  fi
done

if [[ "$missing" -eq 1 ]]; then
  echo "[!] One or more required .env variables are missing. Aborting."
  exit 1
else
  echo "[OK] All required .env variables are set."
fi

# ===========================
# Ensure script runs as SYSTEM_USERNAME
# ===========================
CURRENT_USER="$(whoami)"
if [[ "$CURRENT_USER" != "$SYSTEM_USERNAME" ]]; then
  echo "[*] install.sh must be run as $SYSTEM_USERNAME. Current user: $CURRENT_USER"
  echo "[*] Re-executing as correct user..."
  exec sudo -u "$SYSTEM_USERNAME" bash "$0"
fi

# ===========================
# Unprivileged Port Access for Rootless Podman
# ===========================
echo "[*] Configuring unprivileged port access for Podman..."

SYSCTL_LINE="net.ipv4.ip_unprivileged_port_start=53"
SYSCTL_FILE="/etc/sysctl.conf"

if grep -q "^net.ipv4.ip_unprivileged_port_start=" "$SYSCTL_FILE"; then
  echo "[*] Updating existing setting in $SYSCTL_FILE"
  sudo sed -i "s/^net.ipv4.ip_unprivileged_port_start=.*/$SYSCTL_LINE/" "$SYSCTL_FILE"
else
  echo "[*] Appending new setting to $SYSCTL_FILE"
  echo "$SYSCTL_LINE" | sudo tee -a "$SYSCTL_FILE" > /dev/null
fi

echo "[*] Reloading sysctl settings..."
sudo sysctl -p > /dev/null
sudo sysctl net.ipv4.ip_unprivileged_port_start

if systemctl --quiet is-active podman.socket; then
  echo "[*] Restarting podman.socket to apply changes"
  sudo systemctl restart podman.socket
fi

# ===========================
# Self-tests
# ===========================
echo "[*] Running self-tests..."

if [[ "$(whoami)" != "$SYSTEM_USERNAME" ]]; then
  echo "[FAIL] Not running as $SYSTEM_USERNAME"
  exit 1
else
  echo "[OK] Running as correct user"
fi

if sudo -n true 2>/dev/null; then
  echo "[OK] Passwordless sudo is configured"
else
  echo "[FAIL] Passwordless sudo is not working"
  exit 1
fi

if command -v podman &>/dev/null; then
  if podman info --log-level=error &>/dev/null; then
    echo "[OK] Podman is accessible"
  else
    echo "[WARN] Podman returned an error"
    echo "       You can test manually with: sudo -iu $SYSTEM_USERNAME podman info"
  fi
else
  echo "[FAIL] Podman binary not found"
  exit 1
fi

# ===========================
# Podman Stack Setup
# ===========================
echo "[*] Handing over to podman.sh (running as $SYSTEM_USERNAME)..."
sudo -iu "$SYSTEM_USERNAME" bash "$INSTALLER_PATH/install/scripts/podman.sh"

# ===========================
# OS Hardening and Init
# ===========================
INIT_SCRIPT="$INSTALLER_PATH/install/scripts/init.sh"
if [[ -f "$INIT_SCRIPT" ]]; then
  chmod +x "$INIT_SCRIPT"
  echo "[*] Running init script..."
  bash "$INIT_SCRIPT"
  echo "[OK] Init script completed"
else
  echo "[WARN] No init.sh found — skipping"
fi
