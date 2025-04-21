#!/bin/bash

set -euo pipefail

# ===========================
# Configuration
# ===========================
INSTALLER_PATH="/opt/ztcl"
SYSTEM_USERNAME="ztcl-sysadmin"
ZTCL_VERSION="origin/main"
ZTCL_BRANCH="main"
ZTCL_REPO="https://github.com/ZTCloud-Sysadmin/ztcl.git"
ENV_FILE="$INSTALLER_PATH/sys/config/.env"

EXTERNAL_URL="ztcloud.org"
INTERNAL_URL="ztcloud.ztcl"

DEBUG=false
for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=true ;;
  esac
done

if [[ "$DEBUG" == "true" ]]; then
  echo "[DEBUG] INSTALLER_PATH=$INSTALLER_PATH"
  echo "[DEBUG] SYSTEM_USERNAME=$SYSTEM_USERNAME"
  echo "[DEBUG] ZTCL_VERSION=$ZTCL_VERSION"
  echo "[DEBUG] ZTCL_BRANCH=$ZTCL_BRANCH"
  echo "[DEBUG] ZTCL_REPO=$ZTCL_REPO"
  echo "[DEBUG] ENV_FILE=$ENV_FILE"
  echo "[DEBUG] EXTERNAL_URL=$EXTERNAL_URL"
  echo "[DEBUG] INTERNAL_URL=$INTERNAL_URL"
fi

# ===========================
# Load environment
# ===========================
if [[ -f "$ENV_FILE" ]]; then
  echo "[*] Loading environment variables from .env"
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
fi

# ===========================
# Install required packages
# ===========================
echo "[*] Installing required packages"
apt-get update -qq
apt-get install -y -qq curl sudo podman jq gettext-base git dbus-x11

# ===========================
# Install Tailscale
# ===========================
echo "[*] Installing Tailscale (from bootstrap.sh script)"
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

echo "[*] Ensuring /usr/local/bin is in $SYSTEM_USERNAME's PATH"
echo 'export PATH="$PATH:/usr/local/bin:/root/.local/bin:$PATH"' >> "/home/$SYSTEM_USERNAME/.profile"
chown "$SYSTEM_USERNAME:$SYSTEM_USERNAME" "/home/$SYSTEM_USERNAME/.profile"

# ===========================
# Clone repository
# ===========================
if [[ ! -d "$INSTALLER_PATH/.git" ]]; then
  echo "[*] Cloning ZTCL repo (branch: $ZTCL_BRANCH) to $INSTALLER_PATH"
  git clone --branch "$ZTCL_BRANCH" "$ZTCL_REPO" "$INSTALLER_PATH"
else
  echo "[*] Repo already exists at $INSTALLER_PATH — skipping clone"
fi

chown -R "$SYSTEM_USERNAME:$SYSTEM_USERNAME" "$INSTALLER_PATH"

# ===========================
# Podman & sudo config
# ===========================
if ! getent group podman > /dev/null; then
  echo "[*] Creating 'podman' group"
  groupadd podman
fi

echo "[*] Adding $SYSTEM_USERNAME to sudo and podman groups"
usermod -aG sudo,podman "$SYSTEM_USERNAME"

echo "$SYSTEM_USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$SYSTEM_USERNAME"
chmod 440 "/etc/sudoers.d/$SYSTEM_USERNAME"

# ===========================
# Enable lingering for systemd user services
# ===========================
echo "[*] Enabling lingering for $SYSTEM_USERNAME"
loginctl enable-linger "$SYSTEM_USERNAME"

# ===========================
# Enable Podman socket
# ===========================
systemctl enable --now podman.socket


# ===========================
# Adding Configuration to .env
# ===========================
echo "[*] Ensuring runtime config is written to $ENV_FILE"
mkdir -p "$(dirname "$ENV_FILE")"
cat >> "$ENV_FILE" <<EOF

# Added by bootstrap.sh
SYSTEM_USERNAME="$SYSTEM_USERNAME"
INSTALLER_PATH="$INSTALLER_PATH"
ZTCL_VERSION="$ZTCL_VERSION"
ZTCL_BRANCH="$ZTCL_BRANCH"
EOF

# ===========================
# Launch install.sh
# ===========================
echo "[*] Handing over to install.sh"
sudo -iu "$SYSTEM_USERNAME" bash "$INSTALLER_PATH/install/install.sh"
