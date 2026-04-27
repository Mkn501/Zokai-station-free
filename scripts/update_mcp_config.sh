#!/bin/bash
# Update MCP Config for Kilo Code
# Fetches config from Service Discovery and writes to VS Code globalStorage

SERVICE_URL="http://localhost:8005/mcp-config"
TARGET_DIR="./data/vscode-settings/User/globalStorage/kilocode.kilo-code"
TARGET_FILE="$TARGET_DIR/mcp_settings.json"

echo "Fetching MCP config from $SERVICE_URL..."
CONFIG=$(curl -s $SERVICE_URL)

if [ -z "$CONFIG" ]; then
    echo "Error: Failed to fetch config or empty response."
    exit 1
fi

echo "Ensure target directory exists..."
mkdir -p "$TARGET_DIR"

echo "Writing config to $TARGET_FILE..."
echo "$CONFIG" > "$TARGET_FILE"

echo "Done. Please reload VS Code window to apply changes."
