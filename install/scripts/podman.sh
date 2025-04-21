#!/bin/bash
set -euo pipefail

# ===========================
# Load config and env
# ===========================
source /opt/ztcl/install/scripts/load_config.sh

# Load and validate ownership
source "$INSTALLER_PATH/install/scripts/permission_check.sh"
fix_ownership_if_needed "$INSTALLER_PATH" "$SYSTEM_USERNAME"

# Setup Logfile
LOG_FILE="$INSTALLER_PATH/logs/ztcl-install.log"
touch "$LOG_FILE"; chmod 600 "$LOG_FILE"

log() {
  echo "$@"
  echo "$(date +'%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

DEBUG="${DEBUG:-false}"
[[ "$DEBUG" == "true" ]] && log "[*] Debug mode enabled (podman.sh)"

# ===========================
# Privileged port access for Podman
# ===========================
log "[*] Configuring unprivileged port access..."
SYSCTL_LINE="net.ipv4.ip_unprivileged_port_start=53"
SYSCTL_FILE="/etc/sysctl.conf"

grep -q "^$SYSCTL_LINE" "$SYSCTL_FILE" ||
  echo "$SYSCTL_LINE" | sudo tee -a "$SYSCTL_FILE" > /dev/null

sudo sysctl -p > /dev/null
sudo systemctl restart podman.socket || true

# ===========================
# Self-tests
# ===========================
log "[*] Running podman self-tests..."
[[ "$(whoami)" == "$SYSTEM_USERNAME" ]] || { log "[FAIL] Wrong user"; exit 1; }
sudo -n true 2>/dev/null || { log "[FAIL] Passwordless sudo not working"; exit 1; }
command -v podman >/dev/null || { log "[FAIL] Podman not found"; exit 1; }

# ===========================
# Ensure podman-compose
# ===========================
if ! command -v podman-compose &>/dev/null; then
  log "[*] Installing podman-compose..."
  pipx install podman-compose

  # Export local bin path temporarily and persist for later
  export PATH="$HOME/.local/bin:$PATH"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "/home/$SYSTEM_USERNAME/.profile"
  chown "$SYSTEM_USERNAME:$SYSTEM_USERNAME" "/home/$SYSTEM_USERNAME/.profile"
  log "[*] PATH updated: $PATH"
fi

command -v podman-compose &>/dev/null || { log "[FAIL] podman-compose not available after install"; exit 1; }

# ===========================
# Render templates
# ===========================
log "[*] Rendering configuration templates..."

TEMPLATE_DIR="$INSTALLER_PATH/install/config/templates/sys"
declare -A TEMPLATE_TARGETS=(
  [Caddyfile.template.json]="caddy"
  [Corefile.template]="coredns"
  [headscale.config.template.yaml]="headscale:config.yaml"
  [derpmap.template.json]="headscale"
)

TEMPLATE_ERRORS=0
RENDER_SUMMARY=()

find "$TEMPLATE_DIR" -type f -name "*.template*" | while read -r template; do
  filename="$(basename "$template")"
  mapping="${TEMPLATE_TARGETS[$filename]:-misc}"
  subdir="${mapping%%:*}"
  override_name="${mapping#*:}"
  rendered_name="$([[ "$mapping" == *:* ]] && echo "$override_name" || echo "${filename/.template/}")"
  output_dir="$DATA_PATH/$subdir"
  output_path="$output_dir/$rendered_name"
  mkdir -p "$output_dir"

  content=$(envsubst < "$template")

  if [[ "$filename" == derpmap.template.json ]]; then
    echo "$content" | jq '.Regions[].Nodes[] |= (.DERPPort |= tonumber | .STUNPort |= tonumber)' > "$output_path" || {
      log "[!] Invalid DERP JSON: $rendered_name"
      ((TEMPLATE_ERRORS++)); continue
    }
  elif [[ "$filename" == *.json ]]; then
    echo "$content" | jq . > "$output_path" || {
      log "[!] Invalid JSON: $rendered_name"
      ((TEMPLATE_ERRORS++)); continue
    }
  elif [[ "$filename" == *.yaml || "$filename" == *.yml ]]; then
    echo "$content" > "$output_path"
    if command -v yamllint &>/dev/null; then
      yamllint -d relaxed "$output_path" || {
        log "[!] Invalid YAML: $rendered_name"
        ((TEMPLATE_ERRORS++)); continue
      }
    else
      log "[~] Skipped YAML lint for: $rendered_name"
    fi
  else
    echo "$content" > "$output_path"
  fi

  log "[✓] Rendered: $rendered_name → $output_path"
  RENDER_SUMMARY+=("$rendered_name → $output_path")

  if [[ "$DEBUG" == "true" ]]; then
    echo -e "\n# ====== DEBUG: $rendered_name ======\n"
    cat "$output_path"
    echo -e "\n# ====================================\n"
  fi
done

if [[ "$TEMPLATE_ERRORS" -gt 0 ]]; then
  log "[!] Template rendering failed with $TEMPLATE_ERRORS error(s)"
  exit 1
fi

log "[*] Template render summary:"
for entry in "${RENDER_SUMMARY[@]}"; do log " - $entry"; done

# ===========================
# Launch stack
# ===========================
ZT_COMPOSE="$INSTALLER_PATH/install/config/ztcloud-compose.yaml"
DEST_COMPOSE="$DATA_PATH/ztcloud-compose.yaml"
cp "$ZT_COMPOSE" "$DEST_COMPOSE"

log "[*] Launching Podman Compose stack..."
sudo -iu "$SYSTEM_USERNAME" env $(grep -v '^#' "$ENV_FILE" | xargs -d '\n') podman-compose -f "$DEST_COMPOSE" up -d
log "[✓] Stack launched"

# ===========================
# Save resolved compose config
# ===========================
RESOLVED="$DATA_PATH/ztcloud-compose.resolved.yaml"
log "[*] Saving resolved config → $RESOLVED"
sudo -iu "$SYSTEM_USERNAME" env $(grep -v '^#' "$ENV_FILE" | xargs -d '\n') podman-compose -f "$DEST_COMPOSE" config > "$RESOLVED" 2>> "$LOG_FILE"

# ===========================
# Status Summary
# ===========================
log "[+] Running containers:"
sudo -iu "$SYSTEM_USERNAME" podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

log "[+] Health summary:"
sudo -iu "$SYSTEM_USERNAME" bash -c 'podman inspect --format "{{.Name}}: {{if .State.Healthcheck}}Health={{.State.Healthcheck.Status}}{{else}}No healthcheck{{end}}" $(podman ps -q)'
