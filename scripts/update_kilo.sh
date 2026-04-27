#!/bin/bash
# Kilo Code Update Script
# Updates the Kilo Code extension in the VS Code container.
# Supports running on Host (via docker exec) or Inside Container (direct).

set -e

CONTAINER_NAME="zokai-vs-code"
EXTENSION_ID="kilocode.kilo-code"
LOG_FILE="/tmp/kilo_update.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

update_extension_remote() {
    log "Attempting to update extension: $EXTENSION_ID in container $CONTAINER_NAME (REMOTE)..."
    
    if docker exec "$CONTAINER_NAME" code-server --install-extension "$EXTENSION_ID" --force; then
        log "Extension update successful."
    else
        log "Error: Failed to update extension."
        return 1
    fi
}

update_extension_local() {
    log "Attempting to update extension: $EXTENSION_ID (LOCAL)..."
    
    if code-server --install-extension "$EXTENSION_ID" --force; then
        log "Extension update successful."
    else
        log "Error: Failed to update extension."
        return 1
    fi
}

main() {
    # Check if running on Host (Docker available) or Inside Container
    if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
        # On Host
        if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            log "Error: Container $CONTAINER_NAME is not running."
            exit 1
        fi
        update_extension_remote
    else
        # Inside Container (or no docker access)
        update_extension_local
    fi
}

main "$@"
