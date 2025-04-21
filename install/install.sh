#!/bin/bash
set -euo pipefail

# ===========================
# Load config and env first
# ===========================
CONFIG_FILE="/opt/ztcl/sys/config/config.sh"
ENV_FILE="/opt/ztcl/sys/config/.env"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "[!] config.sh not found at $CONFIG_FILE"
  exit 1
fi

if [[ -f "$ENV_FILE" ]]; then
  set -o allexport; source "$ENV_FILE"; set +o allexport
else
  echo "[!] .env not found at $ENV_FILE"
  exit 1
fi

# ===========================
# Run system ownership + path checks
# ===========================
PERM_CHECK_SCRIPT="$INSTALLER_PATH/install/scripts/permission_check.sh"
if [[ -f "$PERM_CHECK_SCRIPT" ]]; then
  source "$PERM_CHECK_SCRIPT"
  fix_ownership_if_needed "$INSTALLER_PATH" "$SYSTEM_USERNAME"
  ensure_user_path
else
  echo "[!] permission_check.sh not found — skipping ownership and path checks"
fi


# ===========================
# Setup logging
# ===========================
mkdir -p "$INSTALLER_PATH/logs"
LOG_FILE="$INSTALLER_PATH/logs/ztcl-install.log"
touch "$LOG_FILE"; chmod 600 "$LOG_FILE"

log() {
  echo "$@"
  echo "$(date +'%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

DEBUG="${DEBUG:-false}"
[[ "$DEBUG" == "true" ]] && log "[*] DEBUG mode is enabled"


# ===========================
# Validate .env
# ===========================
REQUIRED_ENV_VARS=(
  DATA_PATH HEADSCALE_IMAGE HEADSCALE_NAME HEADSCALE_HTTP_PORT HEADSCALE_STUN_PORT
  ETCD_IMAGE ETCD_NAME ETCD_CLIENT_PORT ETCD_NODE_NAME ETCD_CLUSTER_TOKEN
  COREDNS_IMAGE COREDNS_NAME COREDNS_TCP_PORT COREDNS_UDP_PORT
  CADDY_IMAGE CADDY_NAME CADDY_ADMIN_PORT CADDY_HTTPS_PORT
  ZTCLP_IMAGE ZTCLP_NAME ZTCLP_ADMIN_PORT
  TLS_EMAIL BASE_DOMAIN
)

log "[*] Validating .env variables..."
missing=0
for var in "${REQUIRED_ENV_VARS[@]}"; do
  [[ -z "${!var:-}" ]] && log "[FAIL] Missing: $var" && missing=1
done
[[ "$missing" -eq 1 ]] && exit 1 || log "[OK] All required vars set"

# ===========================
# Confirm correct user
# ===========================
if [[ "$(whoami)" != "$SYSTEM_USERNAME" ]]; then
  log "[*] Switching to $SYSTEM_USERNAME"
  exec sudo -u "$SYSTEM_USERNAME" bash "$0"
fi

# ===========================
# Configure Podman stack
# ===========================
PODMAN_SCRIPT="$INSTALLER_PATH/install/scripts/podman.sh"
if [[ -x "$PODMAN_SCRIPT" ]]; then
  bash "$PODMAN_SCRIPT"
else
  chmod +x "$PODMAN_SCRIPT" && bash "$PODMAN_SCRIPT"
fi

# ===========================
# Install systemd service
# ===========================
SYSTEMD_INSTALL_SCRIPT="$INSTALLER_PATH/install/scripts/systemd_system_pods.sh"
if [[ -f "$SYSTEMD_INSTALL_SCRIPT" ]]; then
  log "[*] Running systemd service installer..."
  bash "$SYSTEMD_INSTALL_SCRIPT"
else
  log "[WARN] systemd_install.sh not found — skipping systemd setup"
fi


# ===========================
# Configure ZTCL Mesh
# ===========================
ZTCL_MESH_SCRIPT="$INSTALLER_PATH/install/scripts/ztcl_mesh.sh"

if [[ -f "$ZTCL_MESH_SCRIPT" ]]; then
  [[ -x "$ZTCL_MESH_SCRIPT" ]] || chmod +x "$ZTCL_MESH_SCRIPT"
  log "[*] Running ZTCL mesh bootstrap..."
  bash "$ZTCL_MESH_SCRIPT"
  log "[✓] Mesh setup complete"
else
  log "[WARN] ztcl_mesh.sh not found — skipping mesh setup"
fi

# ===========================
# Configure firewall
# ===========================
FIREWALL_SCRIPT="$INSTALLER_PATH/install/scripts/firewall.sh"

if [[ -f "$FIREWALL_SCRIPT" ]]; then
  log "[*] Running firewall setup..."
  bash "$FIREWALL_SCRIPT" --log
  log "[✓] Firewall applied"
else
  log "[WARN] firewall.sh not found — skipping"
fi

# ===========================
# Export bin dir to system PATH
# ===========================
if [[ -d "/opt/ztcl/bin" ]]; then
  log "[*] Exporting /opt/ztcl/bin to system PATH"
  echo 'export PATH="/opt/ztcl/bin:$PATH"' | sudo tee /etc/profile.d/ztcl-path.sh > /dev/null
  sudo chmod +x /etc/profile.d/ztcl-path.sh
fi

# ===========================
# Final cleanup
# ===========================
if [[ "${FINAL_CHECK:-false}" == "true" ]]; then
  log "[✓] FINAL_CHECK=true — removing install directory"
  rm -rf "$INSTALLER_PATH/install"
else
  log "[!] FINAL_CHECK=false — install directory retained"
fi

log "========================================"
log "[✓] INSTALL COMPLETE"
log "ZTCL Version: $ZTCL_VERSION"
log "User: $SYSTEM_USERNAME"
log "Mesh IP: $(tailscale ip -4 2>/dev/null || echo unknown)"
log "========================================"
