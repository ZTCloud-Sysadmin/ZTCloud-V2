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

# ===========================
# Template Rendering
# ===========================
echo "[*] Rendering configuration templates..."

TEMPLATE_DIR="$INSTALLER_PATH/install/config/templates/sys"

# Export all known vars so envsubst can use them
set -o allexport
source "$INSTALLER_PATH/install/config.sh"
if [[ -f "$INSTALLER_PATH/install/config/.env" ]]; then
  source "$INSTALLER_PATH/install/config/.env"
fi
set +o allexport

# Use DATA_PATH as base output location
OUTPUT_BASE="${DATA_PATH:-/opt/containers/sys}"

# Ensure base output dir exists and is writable
if [[ ! -d "$OUTPUT_BASE" ]]; then
  echo "[*] Creating DATA_PATH at $OUTPUT_BASE"
  mkdir -p "$OUTPUT_BASE"
fi

if [[ ! -w "$OUTPUT_BASE" ]]; then
  echo "[FAIL] DATA_PATH ($OUTPUT_BASE) is not writable."
  exit 1
fi

# Required environment variables (used in templates or volumes)
REQUIRED_VARS=(
  HEADSCALE_IMAGE HEADSCALE_NAME HEADSCALE_HTTP_PORT HEADSCALE_STUN_PORT HEADSCALE_GRPC_PORT HEADSCALE_SERVER_URL
  COREDNS_IMAGE COREDNS_NAME COREDNS_TCP_PORT COREDNS_UDP_PORT
  CADDY_IMAGE CADDY_NAME CADDY_ADMIN_PORT CADDY_HTTPS_PORT
  ZTCLDNS_IMAGE ZTCLDNS_NAME BASE_DOMAIN
  ETCD_IMAGE ETCD_NAME ETCD_CLIENT_PORT ETCD_NODE_NAME ETCD_CLUSTER_TOKEN
  DERP_REGION_ID DERP_REGION_CODE DERP_REGION_NAME DERP_NODE_NAME DERP_HOSTNAME DERP_IPV4 DERP_IPV6 DERP_PORT STUN_PORT
  TLS_EMAIL DATA_PATH
)

echo "[*] Validating required environment variables..."
missing=0
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "[FAIL] Missing required variable: $var"
    missing=1
  fi
done

if [[ "$missing" -eq 1 ]]; then
  echo "[!] One or more required variables are missing. Aborting template rendering."
  exit 1
fi

# Define filename → target subdir map
declare -A TEMPLATE_TARGETS=(
  [Caddyfile.template.json]="caddy"
  [Corefile.template]="coredns"
  [headscale.config.template.yaml]="headscale"
  [derpmap.template.json]="headscale"
)

# Render templates
find "$TEMPLATE_DIR" -type f -name "*.template*" | while read -r template; do
  filename="$(basename "$template")"
  rendered_name="${filename/.template/}"  # Strip `.template` from name
  subdir="${TEMPLATE_TARGETS[$filename]:-misc}"

  output_dir="$OUTPUT_BASE/$subdir"
  output_path="$output_dir/$rendered_name"

  echo "[*] Rendering: $template → $output_path"
  mkdir -p "$output_dir"
  envsubst < "$template" > "$output_path"
done

echo "[*] Template rendering complete ✅"
