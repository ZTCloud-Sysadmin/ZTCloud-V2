#!/bin/bash

set -euo pipefail

# Define base paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_CONFIG="/opt/ztcl/install/config.sh"

# Load environment from .env if it exists
ENV_FILE="$BASE_DIR/install/config/.env"
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

# === Interactive Config Generation ===
echo "[*] Generating installer config..."

read -rp "Installer path [default: /opt/ztcl]: " INSTALLER_PATH_INPUT
INSTALLER_PATH="${INSTALLER_PATH_INPUT:-/opt/ztcl}"

read -rp "System username [default: ztcl-sysadmin]: " SYSTEM_USERNAME_INPUT
SYSTEM_USERNAME="${SYSTEM_USERNAME_INPUT:-ztcl-sysadmin}"

read -rp "ZTCL version or branch to clone [default: origin/main]: " ZTCL_VERSION_INPUT
ZTCL_VERSION="${ZTCL_VERSION_INPUT:-origin/main}"

# Create installer path
mkdir -p "$INSTALLER_PATH/install"

# Write config
CONFIG_PATH="$INSTALLER_PATH/install/config.sh"
echo "[*] Writing config to $CONFIG_PATH"
cat > "$CONFIG_PATH" <<EOF
INSTALLER_PATH="$INSTALLER_PATH"
SYSTEM_USERNAME="$SYSTEM_USERNAME"
ZTCL_VERSION="$ZTCL_VERSION"
EOF

# Create user if it doesn't exist
if ! id "$SYSTEM_USERNAME" &>/dev/null; then
  echo "[*] Creating system user $SYSTEM_USERNAME"
  useradd -m -s /bin/bash "$SYSTEM_USERNAME"
fi

# Create podman group if it doesn't exist
if ! getent group podman > /dev/null; then
  echo "[*] Creating 'podman' group"
  groupadd podman
fi

# Add user to groups
echo "[*] Adding $SYSTEM_USERNAME to sudo and podman groups"
usermod -aG sudo,podman "$SYSTEM_USERNAME"

# Passwordless sudo
echo "$SYSTEM_USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$SYSTEM_USERNAME"
chmod 440 "/etc/sudoers.d/$SYSTEM_USERNAME"

# Enable Podman socket
systemctl enable --now podman.socket

# === Clone repo ===
echo "[*] Cloning ZTCL repo to $INSTALLER_PATH"
git clone https://github.com/ZTCloud-Sysadmin/ZTCloud-V2.git "$INSTALLER_PATH"
cd "$INSTALLER_PATH"
git checkout "$ZTCL_VERSION"

# Continue to main install
echo "[*] Handing over to install.sh"
sudo -u "$SYSTEM_USERNAME" bash "$INSTALLER_PATH/install/install.sh"
