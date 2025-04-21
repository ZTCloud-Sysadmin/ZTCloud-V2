#!/bin/bash
set -euo pipefail

# ===========================
# Load config and setup logging
# ===========================
source /opt/ztcl/install/scripts/load_config.sh

LOG_FILE="$LOG_DIR/ztcl-install.log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
  echo "$@"
  echo "$(date +'%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

log "========================================"
log "[+] INSTALLER STARTED"
log "INSTALLER_PATH: $INSTALLER_PATH"
log "SYSTEM_USERNAME: $SYSTEM_USERNAME"
log "ZTCL_VERSION: $ZTCL_VERSION"
log "========================================"

# ===========================
# Validate required .env variables
# ===========================
log "[*] Validating required environment variables..."

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
    log "[FAIL] Missing required .env variable: $var"
    missing=1
  fi
done

if [[ "$missing" -eq 1 ]]; then
  log "[!] Aborting due to missing .env values."
  exit 1
else
  log "[OK] All required .env variables are set."
fi

# ===========================
# Ensure correct ownership
# ===========================
log "[*] Ensuring ownership of $INSTALLER_PATH..."
sudo chown -R "$SYSTEM_USERNAME:$SYSTEM_USERNAME" "$INSTALLER_PATH"

# ===========================
# Switch to correct user if needed
# ===========================
CURRENT_USER="$(whoami)"
if [[ "$CURRENT_USER" != "$SYSTEM_USERNAME" ]]; then
  log "[*] install.sh must run as $SYSTEM_USERNAME. Re-executing..."
  exec sudo -u "$SYSTEM_USERNAME" bash "$0"
fi

# ===========================
# Configure port access
# ===========================
log "[*] Configuring unprivileged port access..."

SYSCTL_LINE="net.ipv4.ip_unprivileged_port_start=53"
SYSCTL_FILE="/etc/sysctl.conf"

if grep -q "^net.ipv4.ip_unprivileged_port_start=" "$SYSCTL_FILE"; then
  sudo sed -i "s/^net.ipv4.ip_unprivileged_port_start=.*/$SYSCTL_LINE/" "$SYSCTL_FILE"
else
  echo "$SYSCTL_LINE" | sudo tee -a "$SYSCTL_FILE" > /dev/null
fi

sudo sysctl -p > /dev/null
sudo sysctl net.ipv4.ip_unprivileged_port_start

if systemctl --quiet is-active podman.socket; then
  sudo systemctl restart podman.socket
fi

# ===========================
# Self-tests
# ===========================
log "[*] Running self-tests..."

[[ "$(whoami)" == "$SYSTEM_USERNAME" ]] || { log "[FAIL] Not running as $SYSTEM_USERNAME"; exit 1; }
log "[OK] Running as correct user"

if sudo -n true 2>/dev/null; then
  log "[OK] Passwordless sudo working"
else
  log "[FAIL] Passwordless sudo is not configured"
  exit 1
fi

if command -v podman &>/dev/null && podman info --log-level=error &>/dev/null; then
  log "[OK] Podman is accessible"
else
  log "[WARN] Podman is installed but may not be functional"
fi

# ===========================
# Ensure pipx and podman-compose
# ===========================
if ! command -v podman-compose &>/dev/null; then
  log "[*] Installing podman-compose via pipx..."
  if ! command -v pipx &>/dev/null; then
    sudo apt-get install -y -qq pipx
    pipx ensurepath
  fi
  export PATH="$PATH:$HOME/.local/bin"
  pipx install podman-compose || true
  if ! command -v podman-compose &>/dev/null; then
    log "[FAIL] podman-compose still not available after install"
    exit 1
  fi
fi
log "[OK] podman-compose is available"

# ===========================
# Render configuration templates
# ===========================
log "[*] Rendering configuration templates..."

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
  rendered_name="$([[ "$mapping" == *:* ]] && echo "$override_name" || echo "${filename/.template/}")"
  output_dir="$DATA_PATH/$subdir"
  mkdir -p "$output_dir"
  output_path="$output_dir/$rendered_name"
  log "[*] Rendering: $template → $output_path"
  envsubst < "$template" > "$output_path"
done

# ===========================
# Ensure volume directories exist
# ===========================
log "[*] Ensuring container volume directories..."

VOLUME_DIRS=(
  "$DATA_PATH/headscale"
  "$DATA_PATH/etcd"
  "$DATA_PATH/coredns"
  "$DATA_PATH/caddy"
  "$DATA_PATH/ztcl-panel/config"
)

for dir in "${VOLUME_DIRS[@]}"; do
  mkdir -p "$dir"
  log "[+] Ensured directory: $dir"
done

# ===========================
# Launch Podman Compose stack
# ===========================
ZT_COMPOSE="$INSTALLER_PATH/install/config/ztcloud-compose.yaml"
DEST_COMPOSE="$DATA_PATH/ztcloud-compose.yaml"

[[ -f "$ZT_COMPOSE" ]] || { log "[FAIL] Compose file missing: $ZT_COMPOSE"; exit 1; }
cp "$ZT_COMPOSE" "$DEST_COMPOSE"

log "[*] Launching stack with podman-compose..."
sudo -iu "$SYSTEM_USERNAME" podman-compose -f "$DEST_COMPOSE" up -d
log "[✓] Stack launched successfully"

# ===========================
# Post-launch container status
# ===========================
log "[+] Services running via Podman:"
sudo -iu "$SYSTEM_USERNAME" podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

log "[+] Container health summary:"
sudo -iu "$SYSTEM_USERNAME" bash -c 'podman inspect --format "{{.Name}}: {{if .State.Healthcheck}}Health={{.State.Healthcheck.Status}}{{else}}No healthcheck{{end}}" $(podman ps -q)'

# ===========================
# Run Init and Firewall Scripts
# ===========================
INIT_SCRIPT="$INSTALLER_PATH/install/scripts/init.sh"
FIREWALL_SCRIPT="$INSTALLER_PATH/install/scripts/firewall.sh"

[[ -x "$INIT_SCRIPT" ]] || chmod +x "$INIT_SCRIPT"
[[ -f "$INIT_SCRIPT" ]] && log "[*] Running init script..." && bash "$INIT_SCRIPT" && log "[✓] Init complete"

[[ -f "$FIREWALL_SCRIPT" ]] && log "[*] Running firewall script..." && bash "$FIREWALL_SCRIPT" && log "[✓] Firewall applied"

# ===========================
# Final cleanup (if enabled)
# ===========================
if [[ "${FINAL_CHECK:-false}" == "true" ]]; then
  log "[✓] FINAL_CHECK=true — cleaning up install directory"
  rm -rf "$INSTALLER_PATH/install"
  log "[✓] Removed: $INSTALLER_PATH/install"
else
  log "[!] FINAL_CHECK=false — keeping installer directory"
fi

log "========================================"
log "[✓] INSTALL COMPLETE"
log "ZTCL Version: $ZTCL_VERSION"
log "User: $SYSTEM_USERNAME"
log "Mesh IP: $(tailscale ip -4 2>/dev/null || echo unknown)"
log "========================================"
