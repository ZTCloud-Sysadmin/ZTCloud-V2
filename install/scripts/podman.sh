#!/bin/bash

set -euo pipefail

# Load shared config
source /opt/ztcl/sys/config/load_config.sh

# ===========================
# Ensure pipx and podman-compose
# ===========================
if ! command -v podman-compose &>/dev/null; then
  echo "[*] podman-compose not found. Installing via pipx..."

  if ! command -v pipx &>/dev/null; then
    echo "[*] pipx not found, installing..."
    sudo apt-get install -y -qq pipx
    pipx ensurepath
  fi

  export PATH="$PATH:$HOME/.local/bin"
  pipx install podman-compose

  if ! command -v podman-compose &>/dev/null; then
    echo "[FAIL] podman-compose still not available after install"
    exit 1
  else
    echo "[OK] podman-compose installed"
  fi
else
  echo "[OK] podman-compose already installed"
fi

# ===========================
# Render templates
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

# ===========================
# Copy Compose File
# ===========================
ZT_COMPOSE_SRC="$INSTALLER_PATH/install/config/ztcloud-compose.yaml"
ZT_COMPOSE_DEST="$DATA_PATH/ztcloud-compose.yaml"

if [[ -f "$ZT_COMPOSE_SRC" ]]; then
  echo "[*] Copying compose file..."
  cp "$ZT_COMPOSE_SRC" "$ZT_COMPOSE_DEST"
else
  echo "[FAIL] Compose file missing: $ZT_COMPOSE_SRC"
  exit 1
fi

# ===========================
# Launch stack with Podman Compose
# ===========================
echo "[*] Launching stack with podman-compose..."

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[FAIL] Compose file not found at $COMPOSE_FILE"
  exit 1
fi

podman-compose -f "$COMPOSE_FILE" up -d
echo "[OK] Stack launched"

# ===========================
# Post-launch diagnostics
# ===========================
echo "[+] Services running:"
podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

echo "[+] Container health:"
podman inspect --format '{{.Name}}: {{if .State.Healthcheck}}Health={{.State.Healthcheck.Status}}{{else}}No healthcheck{{end}}' $(podman ps -q)

# ===========================
# Register systemd unit
# ===========================
echo "[*] Setting up systemd unit for stack..."
bash "$INSTALLER_PATH/install/scripts/systemd_install.sh"
