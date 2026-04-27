#!/bin/bash
# Zokai Station — Host URL Watcher
# Polls the shared .open-url-queue file and opens URLs in the system browser.
#
# Works for BOTH prod and dev — url-relay.py (inside the vs-code container)
# writes to scripts/.open-url-queue via the bind-mounted scripts/ volume.
# This script detects changes and runs `open <url>` on macOS.
#
# Start once before running the stack:
#   ./scripts/open-url-watcher.sh &
#
# To stop: kill %1   (or kill $(pgrep -f open-url-watcher))

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUEUE_FILE="$SCRIPT_DIR/.open-url-queue"

echo "[url-watcher] Watching $QUEUE_FILE for URLs to open..."
trap 'echo "[url-watcher] Stopped."; exit 0' SIGINT SIGTERM

while true; do
    if [ -f "$QUEUE_FILE" ] && [ -s "$QUEUE_FILE" ]; then
        URL=$(cat "$QUEUE_FILE" 2>/dev/null)
        if [ -n "$URL" ]; then
            echo "[url-watcher] Opening: $URL"
            open "$URL"
            # Clear immediately after opening
            > "$QUEUE_FILE"
        fi
    fi
    sleep 0.3
done
