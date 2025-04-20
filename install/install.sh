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

  # Ensure ~/.local/bin is in PATH (just in case)
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


# Optional debug
echo "[debug] XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-not set}"

# Test 5: Writable install path
if [[ -w "$INSTALLER_PATH" ]]; then
  echo "[OK] Installer path is writable: $INSTALLER_PATH"
else
  echo "[FAIL] Installer path is not writable: $INSTALLER_PATH"
  exit 1
fi

echo "[*] All self-tests passed ✅"


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

# Define filename → target subdir[:override_filename] map
declare -A TEMPLATE_TARGETS=(
  [Caddyfile.template.json]="caddy"
  [Corefile.template]="coredns"
  [headscale.config.template.yaml]="headscale:config.yaml"
  [derpmap.template.json]="headscale"
  [example_intergration.sh.template]="utils"
)

# Render templates
find "$TEMPLATE_DIR" -type f -name "*.template*" | while read -r template; do
  filename="$(basename "$template")"
  mapping="${TEMPLATE_TARGETS[$filename]:-misc}"
  subdir="${mapping%%:*}"                             # part before colon
  override_name="${mapping#*:}"                      # part after colon

  if [[ "$mapping" == *:* && "$override_name" != "$mapping" ]]; then
    rendered_name="$override_name"
  else
    rendered_name="${filename/.template/}"
  fi

  output_dir="$OUTPUT_BASE/$subdir"
  output_path="$output_dir/$rendered_name"

  echo "[*] Rendering: $template → $output_path"
  mkdir -p "$output_dir"
  envsubst < "$template" > "$output_path"
done

echo "[*] Template rendering complete ✅"

# ===========================
# Podman Registries Configuration
# ===========================
echo "[*] Configuring Podman registries.conf..."

REGISTRY_TEMPLATE="$INSTALLER_PATH/install/config/templates/sys/podman/registries.conf.template"
REGISTRY_RENDERED="$INSTALLER_PATH/install/config/sys/podman/registries.conf"
REGISTRY_TARGET="/etc/containers/registries.conf"

# Optional restart control (set via .env or config.sh)
PODMAN_RESTART_ON_REGISTRY_UPDATE="${PODMAN_RESTART_ON_REGISTRY_UPDATE:-true}"

# Ensure target folder exists
mkdir -p "$(dirname "$REGISTRY_RENDERED")"

if [[ -f "$REGISTRY_TEMPLATE" ]]; then
  echo "[*] Rendering: $REGISTRY_TEMPLATE → $REGISTRY_RENDERED"
  envsubst < "$REGISTRY_TEMPLATE" > "$REGISTRY_RENDERED"

  echo "[*] Copying rendered registries.conf to $REGISTRY_TARGET"
  sudo cp "$REGISTRY_RENDERED" "$REGISTRY_TARGET"

  if [[ "$PODMAN_RESTART_ON_REGISTRY_UPDATE" == "true" ]]; then
    if systemctl is-active --quiet podman.socket; then
      echo "[*] Restarting Podman socket to apply registry config"
      sudo systemctl restart podman.socket
    else
      echo "[WARN] Podman socket is not active — skipping restart"
    fi
  else
    echo "[*] Skipping podman.socket restart (PODMAN_RESTART_ON_REGISTRY_UPDATE=$PODMAN_RESTART_ON_REGISTRY_UPDATE)"
  fi
else
  echo "[WARN] Podman registries.conf.template not found — skipping registry config"
fi



# ===========================
# Podman Image Pull Test
# ===========================
echo "[*] Pulling required container images to validate registry setup..."

IMAGES_TO_PULL=(
  "$HEADSCALE_IMAGE"
  "$ETCD_IMAGE"
  "$COREDNS_IMAGE"
  "$CADDY_IMAGE"
  "$ZTCLDNS_IMAGE"
)

for image in "${IMAGES_TO_PULL[@]}"; do
  echo "[*] Pulling image: $image"
  if podman pull "$image" > /dev/null 2>&1; then
    echo "[OK] Pulled $image"
  else
    echo "[FAIL] Failed to pull image: $image"
    echo "       Check your registries.conf or internet connection"
    exit 1
  fi
done

echo "[*] All required images pulled successfully ✅"

# ===========================
# Verify Rendered Files Exist
# ===========================
echo "[*] Verifying required rendered files..."

REQUIRED_RENDERED_FILES=(
  "$DATA_PATH/coredns/Corefile"
  "$DATA_PATH/caddy/Caddyfile.json"
  "$DATA_PATH/headscale/config.yaml"
  "$DATA_PATH/headscale/derpmap.json"
)

missing=0
for file in "${REQUIRED_RENDERED_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[FAIL] Missing rendered config file: $file"
    missing=1
  else
    echo "[OK] Found: $file"
  fi
done

if [[ "$missing" -eq 1 ]]; then
  echo "[!] One or more config files are missing. Aborting launch."
  exit 1
fi

# ===========================
# Launch with Podman Compose
# ===========================
echo "[*] All config files found. Launching stack with Podman Compose..."

COMPOSE_FILE="$INSTALLER_PATH/install/config/ztcloud-compose.yaml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[FAIL] Compose file not found at $COMPOSE_FILE"
  exit 1
fi

# Use podman-compose to bring everything up
podman-compose -f "$COMPOSE_FILE" up -d

echo "[*] Stack launched successfully ✅"
