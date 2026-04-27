# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
from flask import Flask, jsonify
import json
import logging
import os
import requests

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Service mapping - hardcoded for now based on docker-compose service names
# In a future iteration, this could be dynamic or read from central-config.json more intelligently
MCP_SERVICES = [
    {"name": "gptr-mcp", "url": "http://workstation-gptr-mcp:8000"},
    {"name": "raindrop-mcp", "url": "http://workstation-raindrop-mcp:8001"},
    {"name": "youtube-mcp", "url": "http://workstation-youtube-mcp:8002"}, # This is on host net so might be tricky?

    {"name": "github-mcp", "url": "http://workstation-github-mcp:8004"}
]

# Note on YouTube MCP: It uses 'network_mode: host'. 
# From inside a container on a bridge network (backend-network), accessing 'localhost' refers to the container itself.
# To access host services, we use 'host.docker.internal'.
# So for YouTube MCP, if it listens on 8002 on the host:
MCP_SERVICES[2]["url"] = "http://host.docker.internal:8002"


def fetch_tools_from_service(service_url):
    """Fetch tools from a specific MCP service."""
    try:
        response = requests.get(f"{service_url}/tools", timeout=2)
        if response.status_code == 200:
            data = response.json()
            return data.get("tools", [])
        else:
            logger.warning(f"Failed to fetch tools from {service_url}: Status {response.status_code}")
            return []
    except Exception as e:
        logger.warning(f"Error connecting to {service_url}: {e}")
        return []

@app.route('/health')
def health():
    # Simple check: Can we read our configuration source?
    # Since config is hardcoded or local, we just check internal consistency.
    
    status = "healthy"
    config_state = {"status": "up"}
    
    if not MCP_SERVICES:
        status = "degraded"
        config_state = {"status": "empty", "error": "No services defined"}

    return jsonify({
        'status': status, 
        'service': 'service-discovery',
        'dependencies': {
            'config': config_state
        }
    }), 200

@app.route('/mcp-config')
def get_mcp_config():
    """Aggregate tools from all services and return config."""
    mcp_servers = {}
    
    # Kilo Code requires standard MCP transport.
    # Since our containers currently expose custom HTTP APIs (not standard MCP SSE),
    # the most robust way to connect is via 'docker exec' into the container
    # and running the server in stdio mode (if supported).
    # gptr-mcp server.py supports --stdio.
    
    # We will assume all MCP containers support --stdio or we will map them accordingly.
    
    for service in MCP_SERVICES:
        container_name = f"zokai-{service['name']}"
        
        # Custom logic per service could go here.
        # For gptr-mcp: python server.py --stdio
        
        # Reverting to direct docker command to avoid potential shell wrapping issues in Kilo Code.
        # We rely on 'python -u' to prevent buffering.
        
        command = "docker"
        # -i is essential for stdio.
        args = ["exec", "-i", container_name, "python", "-u", "/app/server.py", "--stdio"]

        # Specifically for YouTube, it might be different (entrypoint.sh?)
        if service['name'] == 'youtube-mcp':
             # YouTube MCP Dockerfile uses ENTRYPOINT ["/entrypoint.sh"]
             # We might need to override.
             # Let's assume the entrypoint handles arguments or we call python directly.
             # Inspecting youtube-mcp would be wise, but sticking to gptr-mcp priority first.
             pass

        mcp_servers[service["name"]] = {
            "command": command,
            "args": args,
            "disabled": False,
            "alwaysAllow": ["deep_research"] # Corrected from autoAllow
        }
        
    return jsonify({"mcpServers": mcp_servers})

@app.route('/tools')
def list_tools():
    """
    Act as a transparent proxy/aggregator. 
    If Kilo Code treats Service Discovery as THE single MCP server, 
    we should return ALL tools here.
    """
    all_tools = []
    for service in MCP_SERVICES:
        tools = fetch_tools_from_service(service["url"])
        for tool in tools:
            # Namespace the tool to avoid collisions?
            # tool['name'] = f"{service['name']}_{tool['name']}"
            all_tools.append(tool)
            
    return jsonify({"tools": all_tools})

@app.route('/tools/<tool_name>', methods=['POST'])
def call_tool_proxy(tool_name):
    # This would require a lookup map to know which service owns which tool.
    # For now, let's just implement the 'list_tools' part to see if they appear.
    # Implementing the actual proxy call is Step 2.
    return jsonify({"error": "Not implemented"}), 501

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8005)