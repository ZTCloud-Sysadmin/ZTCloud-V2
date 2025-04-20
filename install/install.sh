#!/bin/bash

set -euo pipefail

# Ensure PATH includes pipx-installed binaries
export PATH="$PATH:/usr/local/bin:/root/.local/bin"

# ===========================
# Load config and .env
# ===========================
CONFIG_FILE="$(dirname "$0")/config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "[!] config.sh not found at $CONFIG_FILE"
  exit 1
fi

ENV_FILE="$(dirname "$0")/config/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
else
  echo "[!] .env file not found at $ENV_FILE"
  exit 1
fi

# ===========================
# Validate required environment variables from .env
# ===========================
echo "[*] Validating .env environment variables..."

REQUIRED_ENV_VARS=(
  DATA_PATH HEADSCALE_IMAGE HEADSCALE_NAME HEADSCALE_HTTP_PORT HEADSCALE_STUN_PORT
  ETCD_IMAGE ETCD_NAME ETCD_CLIENT_PORT ETCD_NODE_NAME ETCD_CLUSTER_TOKEN
  COREDNS_IMAGE COREDNS_NAME COREDNS_TCP_PORT COREDNS_UDP_PORT
  CADDY_IMAGE CADDY_NAME CADDY_ADMIN_PORT CADDY_HTTPS_PORT
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

# ===========================
# Template Rendering
# ===========================
echo "[*] Rendering configuration templates..."

TEMPLATE_DIR="$INSTALLER_PATH/install/config/templates/sys"

declare -A TEMPLATE_TARGETS=(
  [Caddyfile.template.json]="caddy"
  [Corefile.template]="coredns"
  [headscale.config.template.yaml]="headscale:config.yaml"
  [derpmap.template.json]="headscale"
)

find "$TEMPLATE_DIR" -type f -name "*.template*" | while read -r template; do
  filename="$(basename "$template")"
  mapping="${TEMPLATE_TARGETS[$filename]:-misc}"
  subdir="${mapping%%:*}"
  override_name="${mapping#*:}"

  if [[ "$mapping" == *:* && "$override_name" != "$mapping" ]]; then
    rendered_name="$override_name"
  else
    rendered_name="${filename/.template/}"
  fi

  output_dir="$DATA_PATH/$subdir"
  output_path="$output_dir/$rendered_name"

  echo "[*] Rendering: $template → $output_path"
  mkdir -p "$output_dir"
  envsubst < "$template" > "$output_path"

done

# Ensure empty CoreDNS hosts file exists
COREDNS_HOSTS_FILE="$DATA_PATH/coredns/hosts"
if [[ ! -f "$COREDNS_HOSTS_FILE" ]]; then
  echo "[*] Creating empty CoreDNS hosts file at $COREDNS_HOSTS_FILE"
  touch "$COREDNS_HOSTS_FILE"
fi

echo "[*] Template rendering complete ✅"

# ===========================
# Launch with Podman Compose
# ===========================
echo "[*] All config files found. Launching stack with Podman Compose..."

COMPOSE_FILE="$INSTALLER_PATH/install/config/ztcloud-compose.yaml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[FAIL] Compose file not found at $COMPOSE_FILE"
  exit 1
fi

# Run the stack
podman-compose -f "$COMPOSE_FILE" up -d

echo "[*] Stack launched successfully ✅"

# ===========================
# Post-launch container summary + health
# ===========================
echo "[+] Services running via Podman (as $SYSTEM_USERNAME):"
sudo -iu "$SYSTEM_USERNAME" podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

echo "[+] Container health status:"
sudo -iu "$SYSTEM_USERNAME" bash -c 'podman inspect --format "{{.Name}}: {{if .State.Healthcheck}}Health={{.State.Healthcheck.Status}}{{else}}No healthcheck{{end}}" $(podman ps -q)'
