#!/bin/bash
set -euo pipefail

# ===========================
# Load config + env + logging
# ===========================
source /opt/ztcl/install/scripts/load_config.sh

LOG_FILE="$LOG_DIR/ztcl-final.log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
  echo "$@"
  echo "$(date +'%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

log "========================================"
log "[+] final_check.sh STARTED"
log "ZTCL_NETWORK: $ZTCL_NETWORK"
log "INSTALLER_PATH: $INSTALLER_PATH"
log "========================================"

log "[✓] final_check.sh was called successfully (placeholder mode)."

# Always succeed for now
exit 0
