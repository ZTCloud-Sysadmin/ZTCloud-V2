#!/bin/bash

set -euo pipefail

# Ensure PATH includes pipx-installed binaries
export PATH="$PATH:/usr/local/bin:/root/.local/bin"

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

# ===========================
# Unprivileged Port Access for Rootless Podman (SYSTEM_USERNAME only)
# ===========================
if [[ "$CURRENT_USER" == "$SYSTEM_USERNAME" ]]; then
  echo "[*] Configuring system to allow $SYSTEM_USERNAME to bind to privileged ports..."

  SYSCTL_LINE="net.ipv4.ip_unprivileged_port_start=53"
  SYSCTL_FILE="/etc/sysctl.conf"

  if grep -q "^net.ipv4.ip_unprivileged_port_start=" "$SYSCTL_FILE"; then
    echo "[*] Updating existing unprivileged port setting in $SYSCTL_FILE"
    sudo sed -i "s/^net.ipv4.ip_unprivileged_port_start=.*/$SYSCTL_LINE/" "$SYSCTL_FILE"
  else
    echo "[*] Appending unprivileged port setting to $SYSCTL_FILE"
    echo "$SYSCTL_LINE" | sudo tee -a "$SYSCTL_FILE" > /dev/null
  fi

  echo "[*] Reloading sysctl settings..."
  sudo sysctl -p > /dev/null
  echo "[*] Verifying sysctl setting:"
  sudo sysctl net.ipv4.ip_unprivileged_port_start

  if systemctl --quiet is-active podman.socket; then
    echo "[*] Restarting podman.socket to apply privilege changes"
    sudo systemctl restart podman.socket
  fi
else
  echo "[WARN] Skipping unprivileged port fix — not running as $SYSTEM_USERNAME"
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

# ===========================
# Self-tests
# ===========================
echo "[*] Running self-tests..."

# Test 1: Confirm running as correct user
EXPECTED_USER="$SYSTEM_USERNAME"
ACTUAL_USER="$(whoami)"
if [[ "$ACTUAL_USER" != "$EXPECTED_USER" ]]; then
  echo "[FAIL] Not running as $EXPECTED_USER (current: $ACTUAL_USER)"
  exit 1
else
  echo "[OK] Running as correct user: $ACTUAL_USER"
fi

# Test 2: Check passwordless sudo
if sudo -n true 2>/dev/null; then
  echo "[OK] Passwordless sudo is configured"
else
  echo "[FAIL] Passwordless sudo is not working for $ACTUAL_USER"
  exit 1
fi

# Test 3: Check Podman access (improved test)
if command -v podman &>/dev/null; then
  if podman info --log-level=error &>/dev/null; then
    echo "[OK] Podman is accessible"
  else
    echo "[WARN] Podman is installed but returned an error"
    echo "       Possibly not a full login shell or XDG session not active"
    echo "       You can test manually with: sudo -iu $SYSTEM_USERNAME podman info"
  fi
else
  echo "[FAIL] Podman binary not found"
  exit 1
fi

# ===========================
# Ensure pipx and podman-compose (install if missing)
# ===========================
if ! command -v podman-compose &>/dev/null; then
  echo "[*] podman-compose not found. Attempting to install via pipx..."

  if ! command -v pipx &>/dev/null; then
    echo "[*] pipx not found, installing via apt..."
    sudo apt-get install -y -qq pipx
    pipx ensurepath
  fi

  export PATH="$PATH:$HOME/.local/bin"
  echo "[*] Installing podman-compose..."
  pipx install podman-compose

  if ! command -v podman-compose &>/dev/null; then
    echo "[FAIL] podman-compose still not available after install"
    exit 1
  else
    echo "[OK] podman-compose installed successfully"
  fi
else
  echo "[OK] podman-compose already installed"
fi
