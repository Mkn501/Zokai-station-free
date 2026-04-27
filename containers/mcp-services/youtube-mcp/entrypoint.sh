#!/bin/bash

# Entrypoint script for YouTube MCP service
# Runs FastMCP server with SSE transport for cloud or STDIO for local

# Function to handle signals
cleanup() {
    echo "Received shutdown signal, exiting..."
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Default to SSE if MCP_TRANSPORT is not set
export MCP_TRANSPORT="${MCP_TRANSPORT:-sse}"

echo "YouTube MCP container starting..."
echo "Transport: ${MCP_TRANSPORT}"
echo "Port: ${PORT:-8002}"

# Run the FastMCP server
exec python -u simple_youtube_mcp.py