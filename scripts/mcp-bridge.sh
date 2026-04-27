#!/bin/bash
# MCP Bridge Script - Runs inside VS Code container to communicate with Docker services
# Refactored to use modular Python bridge (Dec 2025)

SERVICE_NAME=$1
shift

# Resolve script directory to allow execution from Host or Container
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delegate to the Python bridge module
# Pass the service name as the first argument, and any remaining arguments (though currently unused)
# Standardize on python3
exec python3 "$DIR/mcp_bridge.py" "$SERVICE_NAME" "$@"