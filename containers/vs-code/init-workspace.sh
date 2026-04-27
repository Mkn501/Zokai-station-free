#!/bin/bash
set -e

echo "Initializing workspace..."

# Create default workspace directories
mkdir -p /home/workspace-user/workspaces/{notes,outputs}

# Create default task file if missing (used by mcp-tasks service + dashboard)
if [ ! -f "/home/workspace-user/workspaces/antigravity_tasks.md" ]; then
    cat > /home/workspace-user/workspaces/antigravity_tasks.md << 'TASKS'
# Tasks

## In Progress

## To Do

## Backlog

## Done

## Notes

## Deleted
TASKS
    echo "Task file initialized."
fi

# Auto-Initialize Zokai Notes workspace if missing
if [ ! -d "/home/workspace-user/workspaces/notes" ] && [ -d "/home/workspace-user/zokai-notes-seed" ]; then
    echo "Initializing Zokai Notes workspace from seed..."
    cp -r /home/workspace-user/zokai-notes-seed/notes /home/workspace-user/workspaces/notes
    # Copy .vscode settings for file ignore config
    if [ -d "/home/workspace-user/zokai-notes-seed/.vscode" ]; then
        cp -r /home/workspace-user/zokai-notes-seed/.vscode /home/workspace-user/workspaces/.vscode
    fi
    echo "Zokai Notes workspace initialized with wiki-linked starter notes."
fi

# Ensure .zokai/templates exists at workspace root (from seed on first run)
if [ ! -d "/home/workspace-user/workspaces/.zokai/templates" ] && [ -d "/home/workspace-user/zokai-notes-seed/notes/templates" ]; then
    mkdir -p /home/workspace-user/workspaces/.zokai
    cp -r /home/workspace-user/zokai-notes-seed/notes/templates /home/workspace-user/workspaces/.zokai/templates
    echo "Zokai templates initialized at .zokai/templates"
fi

# Seed/update station documentation into .zokai/ (ALWAYS overwrite — station-managed, not user content)
# This ensures users get the latest capabilities doc on every container rebuild/update.
if [ -d "/home/workspace-user/zokai-docs-seed" ]; then
    mkdir -p /home/workspace-user/workspaces/.zokai
    set +e  # Don't exit on copy failures (Windows Docker bind mounts can be flaky)
    for _seedfile in /home/workspace-user/zokai-docs-seed/*; do
        _basename=$(basename "$_seedfile")
        cp -f "$_seedfile" "/home/workspace-user/workspaces/.zokai/$_basename" && \
            echo "  + $_basename" || \
            echo "  FAILED to copy $_basename"
    done
    set -e
    echo "Station docs updated in .zokai/"
fi

# Ensure Foam finds templates via symlink: .foam/templates -> .zokai/templates
# Foam v0.29.2 hardcodes .foam/templates with no configurable override
if [ -d "/home/workspace-user/workspaces/.zokai/templates" ] && [ ! -L "/home/workspace-user/workspaces/.foam/templates" ]; then
    mkdir -p /home/workspace-user/workspaces/.foam
    rm -rf /home/workspace-user/workspaces/.foam/templates 2>/dev/null || true
    ln -s /home/workspace-user/workspaces/.zokai/templates /home/workspace-user/workspaces/.foam/templates
    echo "Foam template symlink created: .foam/templates -> .zokai/templates"
fi

# Clean up stale legacy config files from existing workspaces (preserves user content)
for CLEANUP_DIR in "/home/workspace-user/workspaces" "/home/workspace-user/workspaces/notes"; do
    if [ -d "$CLEANUP_DIR" ]; then
        for dendron_file in "$CLEANUP_DIR/.dendron.cache.json" "$CLEANUP_DIR/.dendron.port" "$CLEANUP_DIR/.dendron.ws" "$CLEANUP_DIR/dendron.yml" "$CLEANUP_DIR/root.schema.yml" "$CLEANUP_DIR/dendron.code-workspace" "$CLEANUP_DIR/root.md"; do
            if [ -f "$dendron_file" ]; then
                echo "  Cleaning up stale legacy file: $dendron_file"
                rm -f "$dendron_file"
            fi
        done
    fi
done

# Clean up stale empty directories from previous workspace layouts
for stale_dir in "/home/workspace-user/workspaces/projects" "/home/workspace-user/workspaces/scripts" "/home/workspace-user/workspaces/temp" "/home/workspace-user/workspaces/.pytest_cache"; do
    if [ -d "$stale_dir" ]; then
        # Only remove if empty or is .pytest_cache
        if [ "$(basename $stale_dir)" = ".pytest_cache" ] || [ -z "$(ls -A $stale_dir 2>/dev/null)" ]; then
            echo "  Removing stale directory: $(basename $stale_dir)"
            rm -rf "$stale_dir"
        fi
    fi
done

# Initialize git in workspaces for version tracking
if [ ! -d "/home/workspace-user/workspaces/.git" ]; then
    echo "Initializing git repository for note version tracking..."
    cd /home/workspace-user/workspaces
    git init -q
    git config user.name "Zokai Station"
    git config user.email "station@zokai.ai"
    git add -A 2>/dev/null
    git commit -q -m "Initial workspace snapshot" 2>/dev/null || true
    echo "Git repository initialized."
fi


# Source centralized path definitions
if [ -f "/home/workspace-user/config/paths.env" ]; then
    source /home/workspace-user/config/paths.env
else
    echo "Warning: paths.env not found, using defaults"
    # Fallback/Defaults if file is missing (though it should be mounted)
    YOUTUBE_OUTPUT_DIR="/home/workspace-user/Documents/youtube_output"
    YOUTUBE_OUTPUT_LINK_WORKSPACE="/home/workspace-user/workspaces/notes/youtube_output"
    YOUTUBE_OUTPUT_LINK_HOME="/home/workspace-user/youtube_output"
fi

# Setup YouTube output directory access
# We use the centralized paths
if [ -d "$YOUTUBE_OUTPUT_DIR" ]; then
    echo "Setting up YouTube output directory access..."
    
    # Link to workspace notes
    mkdir -p "$(dirname "$YOUTUBE_OUTPUT_LINK_WORKSPACE")"
    ln -sf "$YOUTUBE_OUTPUT_DIR" "$YOUTUBE_OUTPUT_LINK_WORKSPACE"
    
    # Link to home directory for convenience
    ln -sf "$YOUTUBE_OUTPUT_DIR" "$YOUTUBE_OUTPUT_LINK_HOME"
    
    echo "YouTube output symlinks created successfully"
else
    echo "Warning: YouTube output directory not found at $YOUTUBE_OUTPUT_DIR"
fi

# Create welcome file
cat > /home/workspace-user/workspaces/README.md << 'WELCOME'
# Welcome to Your Fully Containerized Workstation

This is your personal development environment running entirely in Docker containers.

## Quick Start

1. **Open a folder**: Use File > Open Folder to navigate to your projects
2. **Install extensions**: Use the Extensions view (Ctrl+Shift+X) to install additional tools
3. **Configure settings**: Edit settings.json to customize your environment

## Available Services

- **VS Code Server**: This editor (port 8080)
- **MCP Services**: Various tools and integrations (ports 8000-8004)
- **Qdrant Vector DB**: Semantic search (port 6333)
- **Redis Cache**: Caching layer (port 6379)
- **Embedding Server**: Centralized text embeddings (port 7997)

## Configuration

Your configuration is stored in:
- VS Code settings: `~/.local/share/code-server/User/`
- Extensions: `~/.local/share/code-server/extensions/`
- Workspaces: `/home/workspace-user/workspaces/`

## Getting Help

Check the documentation in the project repository for more detailed information.

Happy coding! 🚀
WELCOME

# Create default code-workspace file for Zokai Notes / Root Access
cat > /home/workspace-user/workspaces/zokai.code-workspace << 'WORKSPACE_CONFIG'
{
	"folders": [
		{
			"path": "."
		}
	],
	"settings": {
		"workbench.sideBar.location": "left",
		"workbench.auxiliaryBar.visible": true,
		"workbench.view.kilo-code-ActivityBar.location": "auxiliary",
		"workbench.view.foam-vscode.location": "sidebar",
		"foam.templates.templateDirectory": ".zokai/templates",
		"files.exclude": {
			"**/.foam": true,
			"**/.vscode": true,
			"**/.git": true,
			"**/.kilocode": true,
			"**/.gemini": true,
			"**/.aim": true
		}
	}
}
WORKSPACE_CONFIG

# Legacy Support: Copy mcp-bridge.sh to correct locations
# 1. Root home (older configs)
# 2. .local/bin (newer configs from configure-kilo-code.sh)
if [ -f "/home/workspace-user/scripts/mcp-bridge.sh" ]; then
    # Location 1
    cp /home/workspace-user/scripts/mcp-bridge.sh /home/workspace-user/mcp-bridge.sh
    chmod +x /home/workspace-user/mcp-bridge.sh
    
    # Location 2
    mkdir -p /home/workspace-user/.local/bin
    cp /home/workspace-user/scripts/mcp-bridge.sh /home/workspace-user/.local/bin/mcp-bridge.sh
    chmod +x /home/workspace-user/.local/bin/mcp-bridge.sh
    
    echo "Restored mcp-bridge.sh to legacy locations"
fi

# NOTE: Legacy compatibility shim removed (WO-3: Dendron → Foam → Zokai Notes)

echo "Workspace initialized successfully"