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

# Optional debug
echo "[debug] XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-not set}"

# Test 4: Writable install path
if [[ -w "$INSTALLER_PATH" ]]; then
  echo "[OK] Installer path is writable: $INSTALLER_PATH"
else
  echo "[FAIL] Installer path is not writable: $INSTALLER_PATH"
  exit 1
fi

echo "[*] All self-tests passed ✅"
