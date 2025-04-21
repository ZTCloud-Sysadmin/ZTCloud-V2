#!/bin/bash
set -euo pipefail

# ===========================
# Static config
# ===========================
INSTALLER_PATH="/opt/ztcl"
SYSTEM_USERNAME="ztcl-sysadmin"
ZTCL_VERSION="origin/main"
ZTCL_BRANCH="${ZTCL_VERSION#origin/}"
CONFIG_DIR="$INSTALLER_PATH/sys/config"
CONFIG_PATH="$CONFIG_DIR/config.sh"
PERMANENT_ENV_PATH="$CONFIG_DIR/.env"
CLONE_URL="https://github.com/ZTCloud-Sysadmin/ZTCloud-V2.git"

# ===========================
# Install required system packages
# ===========================
echo "[*] Installing required packages..."
apt-get update -qq
apt-get install -y -qq curl sudo podman jq gettext-base git dbus-x11 ufw

# ===========================
# Install Tailscale
# ===========================
echo "[*] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

if ! command -v tailscale &>/dev/null; then
  echo "[!] Tailscale installation failed"
  exit 1
fi

tailscaled --version && echo "[*] Tailscale installed successfully"

# ===========================
# Create system user
# ===========================
if ! id "$SYSTEM_USERNAME" &>/dev/null; then
  echo "[*] Creating system user $SYSTEM_USERNAME"
  useradd -m -s /bin/bash "$SYSTEM_USERNAME"
else
  echo "[*] User $SYSTEM_USERNAME already exists"
fi

# Add to groups and enable passwordless sudo
echo "[*] Adding $SYSTEM_USERNAME to sudo and podman groups"
usermod -aG sudo,podman "$SYSTEM_USERNAME"
echo "$SYSTEM_USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$SYSTEM_USERNAME"
chmod 440 "/etc/sudoers.d/$SYSTEM_USERNAME"

# Ensure pipx path available
echo "[*] Ensuring PATH in user profile"
echo 'export PATH="$PATH:/usr/local/bin:/root/.local/bin:$PATH"' >> "/home/$SYSTEM_USERNAME/.profile"
chown "$SYSTEM_USERNAME:$SYSTEM_USERNAME" "/home/$SYSTEM_USERNAME/.profile"

# ===========================
# Clone repo
# ===========================
if [[ ! -d "$INSTALLER_PATH/.git" ]]; then
  echo "[*] Cloning ZTCL repo (branch: $ZTCL_BRANCH) to $INSTALLER_PATH"
  git clone --branch "$ZTCL_BRANCH" "$CLONE_URL" "$INSTALLER_PATH"
else
  echo "[*] Repo already exists at $INSTALLER_PATH — skipping clone"
fi

# Fix ownership for everything
echo "[*] Setting ownership of $INSTALLER_PATH to $SYSTEM_USERNAME"
chown -R "$SYSTEM_USERNAME:$SYSTEM_USERNAME" "$INSTALLER_PATH"

# ===========================
# Write config + copy .env
# ===========================
echo "[*] Creating config directory at $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

ENV_FILE="$INSTALLER_PATH/install/config/.env"
if [[ -f "$ENV_FILE" ]]; then
  echo "[*] Moving .env to $PERMANENT_ENV_PATH"
  cp "$ENV_FILE" "$PERMANENT_ENV_PATH"
else
  echo "[!] .env not found at $ENV_FILE — aborting"
  exit 1
fi

echo "[*] Writing config to $CONFIG_PATH"
cat > "$CONFIG_PATH" <<EOF
INSTALLER_PATH="$INSTALLER_PATH"
SYSTEM_USERNAME="$SYSTEM_USERNAME"
ZTCL_VERSION="$ZTCL_VERSION"
EOF

# ===========================
# Enable Podman + lingering
# ===========================
echo "[*] Enabling lingering for $SYSTEM_USERNAME"
loginctl enable-linger "$SYSTEM_USERNAME"

echo "[*] Enabling Podman socket"
systemctl enable --now podman.socket

# ===========================
# Launch installer
# ===========================
echo "[*] Handing over to install.sh"
sudo -iu "$SYSTEM_USERNAME" bash "$INSTALLER_PATH/install/install.sh"