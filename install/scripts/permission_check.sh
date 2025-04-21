#!/bin/bash
set -euo pipefail

# ===========================
# Load config
# ===========================
CONFIG_FILE="/opt/ztcl/sys/config/config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "[!] Missing config.sh for permission check"
  exit 1
fi

# ===========================
# Setup logging
# ===========================
LOG_FILE="$INSTALLER_PATH/logs/ztcl-permission-check.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"; chmod 600 "$LOG_FILE"

log() {
  echo "$@"
  echo "$(date +'%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

# ===========================
# Fix directory ownership
# ===========================
fix_ownership_if_needed() {
  local target_path="${1:-$INSTALLER_PATH}"
  local expected_owner="${2:-$SYSTEM_USERNAME}"

  if [[ ! -d "$target_path" ]]; then
    log "[!] Path does not exist: $target_path"
    exit 1
  fi

  local actual_owner
  actual_owner=$(stat -c '%U' "$target_path")

  if [[ "$actual_owner" != "$expected_owner" ]]; then
    log "[!] Invalid ownership: $target_path → $actual_owner (expected: $expected_owner)"
    log "[*] Attempting to fix ownership..."
    sudo chown -R "$expected_owner:$expected_owner" "$target_path"
    log "[✓] Ownership corrected: $target_path → $expected_owner"
  else
    log "[✓] Ownership OK: $target_path → $expected_owner"
  fi
}

# ===========================
# Ensure PATH for system user
# ===========================
ensure_user_path() {
  local profile="/home/$SYSTEM_USERNAME/.profile"
  local path_snippet="/usr/local/bin:/root/.local/bin:/usr/sbin:/sbin"

  if [[ ! -f "$profile" ]]; then
    log "[!] Profile not found: $profile"
    return
  fi

  if ! grep -q "$path_snippet" "$profile"; then
    log "[*] Extending PATH for $SYSTEM_USERNAME in $profile"
    echo "export PATH=\"\$PATH:$path_snippet\"" >> "$profile"
    chown "$SYSTEM_USERNAME:$SYSTEM_USERNAME" "$profile"
    log "[✓] PATH updated for $SYSTEM_USERNAME"
  else
    log "[~] PATH already configured in $profile"
  fi
}
