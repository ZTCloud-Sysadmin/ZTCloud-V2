#!/bin/bash

set -euo pipefail

# Define base paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$BASE_DIR/install/config/.env"

# Load environment from .env if it exists
if [[ -f "$ENV_FILE" ]]; then
  echo "[*] Loading environment variables from .env"
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
fi

# Ensure required system packages
echo "[*] Installing required packages"
apt-get update -qq
apt-get install -y -qq curl sudo podman jq gettext-base git

# === Interactive Config Input ===
echo "[*] Gathering installer settings..."

read -rp "Installer path [default: /opt/ztcl]: " INSTALLER_PATH_INPUT
INSTALLER_PATH="${INSTALLER_PATH_INPUT:-/opt/ztcl}"

read -rp "System username [default: ztcl-sysadmin]: " SYSTEM_USERNAME_INPUT
SYSTEM_USERNAME="${SYSTEM_USERNAME_INPUT:-ztcl-sysadmin}"

read -rp "ZTCL version or branch to clone [default: origin/main]: " ZTCL_VERSION_INPUT
ZTCL_VERSION="${ZTCL_VERSION_INPUT:-origin/main}"

# Strip "origin/" prefix if provided
ZTCL_BRANCH="${ZTCL_VERSION#origin/}"

# === Create user if needed (before chown) ===
if ! id "$SYSTEM_USERNAME" &>/dev/null; then
  echo "[*] Creating system user $SYSTEM_USERNAME"
  useradd -m -s /bin/bash "$SYSTEM_USERNAME"
fi

# Ensure pipx path is available for the system user
echo "[*] Ensuring /usr/local/bin is in $SYSTEM_USERNAME's PATH"
echo 'export PATH="$PATH:/usr/local/bin:/root/.local/bin:$PATH"' >> "/home/$SYSTEM_USERNAME/.profile"
chown "$SYSTEM_USERNAME:$SYSTEM_USERNAME" "/home/$SYSTEM_USERNAME/.profile"

# === Clone repo ===
echo "[*] Cloning ZTCL repo (branch: $ZTCL_BRANCH) to $INSTALLER_PATH"
git clone --branch "$ZTCL_BRANCH" https://github.com/ZTCloud-Sysadmin/ZTCloud-V2.git "$INSTALLER_PATH"

# Fix ownership so system user has write access
chown -R "$SYSTEM_USERNAME:$SYSTEM_USERNAME" "$INSTALLER_PATH"

# === Write config.sh ===
CONFIG_PATH="$INSTALLER_PATH/install/config.sh"
echo "[*] Writing config to $CONFIG_PATH"
cat > "$CONFIG_PATH" <<EOF
INSTALLER_PATH="$INSTALLER_PATH"
SYSTEM_USERNAME="$SYSTEM_USERNAME"
ZTCL_VERSION="$ZTCL_VERSION"
EOF

# Create podman group if needed
if ! getent group podman > /dev/null; then
  echo "[*] Creating 'podman' group"
  groupadd podman
fi

# Add to groups and enable passwordless sudo
echo "[*] Adding $SYSTEM_USERNAME to sudo and podman groups"
usermod -aG sudo,podman "$SYSTEM_USERNAME"
echo "$SYSTEM_USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$SYSTEM_USERNAME"
chmod 440 "/etc/sudoers.d/$SYSTEM_USERNAME"

# Enable lingering for systemd user services (for rootless Podman)
echo "[*] Enabling lingering for $SYSTEM_USERNAME"
loginctl enable-linger "$SYSTEM_USERNAME"

# Install dbus-x11 to clean up Podman systemd/dbus warnings
echo "[*] Installing dbus-x11 to silence Podman warnings"
apt-get install -y -qq dbus-x11

# Enable Podman socket
systemctl enable --now podman.socket

# === Continue to install.sh as the system user (with full login shell) ===
echo "[*] Handing over to install.sh"
sudo -iu "$SYSTEM_USERNAME" bash "$INSTALLER_PATH/install/install.sh"
