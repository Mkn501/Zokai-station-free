#!/bin/bash
# Fixed Kilo Code Configuration Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_step() {
  echo -e "${GREEN}=== $1 ===${NC}"
}

print_info() {
  echo -e "${YELLOW}$1${NC}"
}

print_error() {
  echo -e "${RED}Error: $1${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

# Get the container ID of the VS Code container
# CRITICAL: Docker's -f name= does SUBSTRING matching, so "zokai-vs-code"
# matches "zokai-mkn-vs-code". This caused the Free tier installer to
# overwrite MKN's config repeatedly (retros: 2026-04-12, 04-18, 04-26).
# Fix: when ZOKAI_INSTANCE is set, use ONLY exact matching. NEVER fall back
# to other tiers — if the target container isn't running, FAIL.
get_vscode_container() {
    # Exact match when ZOKAI_INSTANCE is known (always set by DMG/ZIP installers)
    if [ -n "$ZOKAI_INSTANCE" ]; then
        local exact_name="${ZOKAI_INSTANCE}-vs-code"
        # Try running containers first
        local id=$(docker ps --format '{{.ID}} {{.Names}}' | grep -w "$exact_name" | head -1 | awk '{print $1}')
        if [ -n "$id" ]; then
            echo "$id"
            return
        fi
        # Also try non-running containers (Created state) — needed when docker compose
        # partially starts (e.g. one service fails, vs-code is Created but not Running)
        id=$(docker ps -a --format '{{.ID}} {{.Names}}' | grep -w "$exact_name" | head -1 | awk '{print $1}')
        if [ -n "$id" ]; then
            echo "$id"
            return
        fi
        # ZOKAI_INSTANCE is set but container not found — return empty, do NOT
        # fall through to the legacy fallback list. This prevents cross-tier
        # contamination (e.g., Free installer targeting MKN container).
        return
    fi

    # Fallback: try exact names in priority order (legacy installs without ZOKAI_INSTANCE)
    local names="zokai-free-vs-code zokai-pro-vs-code zokai-dev-vs-code zokai-mkn-vs-code workstation-vs-code"
    for name in $names; do
        local id=$(docker ps --format '{{.ID}} {{.Names}}' | grep -w "$name" | head -1 | awk '{print $1}')
        if [ -n "$id" ]; then
            echo "$id"
            return
        fi
    done
}

# Main function
main() {
    # Ensure script runs from the correct directory
    cd "$(dirname "$0")/.."
    
    # Extract only the vars the script needs — sourcing .env fails when values have spaces
    # Try .env first, then tier-specific .env files as fallback
    local _envfile=""
    for _candidate in ".env" ".env.free" ".env.pro" ".env.mkn"; do
        if [ -f "$_candidate" ]; then
            _envfile="$_candidate"
            break
        fi
    done

    if [ -n "$_envfile" ]; then
        [ -z "$TIER" ]                  && TIER=$(grep '^TIER='                  "$_envfile" | cut -d= -f2- | tr -d '"')
        [ -z "$PROFILE" ]               && PROFILE=$(grep '^PROFILE='               "$_envfile" | cut -d= -f2- | tr -d '"')
        [ -z "$ENABLE_EXTERNAL_TOOLS" ] && ENABLE_EXTERNAL_TOOLS=$(grep '^ENABLE_EXTERNAL_TOOLS=' "$_envfile" | cut -d= -f2- | tr -d '"')
        [ -z "$LLM_MODEL" ]             && LLM_MODEL=$(grep '^LLM_MODEL='             "$_envfile" | cut -d= -f2- | tr -d '"')
        [ -z "$ZOKAI_INSTANCE" ]         && ZOKAI_INSTANCE=$(grep '^ZOKAI_INSTANCE='   "$_envfile" | cut -d= -f2- | tr -d '"')
        export TIER PROFILE ENABLE_EXTERNAL_TOOLS LLM_MODEL ZOKAI_INSTANCE
    fi

    # Default ENABLE_EXTERNAL_TOOLS to 'true' — only Privacy Mode sets it to 'false'
    ENABLE_EXTERNAL_TOOLS="${ENABLE_EXTERNAL_TOOLS:-true}"

    # Derive TIER from PROFILE for backward compat (old .env files)
    if [ -z "$TIER" ] && [ -n "$PROFILE" ]; then
        case "$PROFILE" in
            ff)     TIER="free" ;;
            pro)    TIER="pro" ;;
            hybrid) TIER="mkn" ;;
            *)      TIER="free" ;;
        esac
    fi
    TIER="${TIER:-free}"
    
    print_step "Configuring Kilo Code"
    
    # Get VS Code container with retry
    local container_id=""
    local max_retries=10
    local retry_count=0
    
    while [ -z "$container_id" ] && [ $retry_count -lt $max_retries ]; do
        container_id=$(get_vscode_container)
        if [ -z "$container_id" ]; then
            print_info "Waiting for VS Code container to be ready... ($((retry_count + 1))/$max_retries)"
            sleep 3
            retry_count=$((retry_count + 1))
        fi
    done

    if [ -z "$container_id" ]; then
        print_error "VS Code container not found after waiting"
        exit 1
    fi
    
    print_success "Found VS Code container: $container_id"
    
    # Create Kilo Code directories
    print_step "Creating Kilo Code directories"
    docker exec "$container_id" mkdir -p /home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings
    
    # Copy settings files
    # Create settings directory
    docker exec "$container_id" mkdir -p /home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings
    
    # Copy settings files
    print_step "Copying Kilo Code settings"
    
    # Determine which config file to use
    local config_source="config/kilo/kilo-settings-import.json"
    local enable_external="true"
    
    if [ -f ".env" ]; then
        enable_external=$(grep "^ENABLE_EXTERNAL_TOOLS=" .env | cut -d '=' -f2 | tr '[:upper:]' '[:lower:]')
    fi
    
    # Config source selection based on TIER (with PROFILE fallback)
    if [ "$TIER" = "mkn" ]; then
        print_info "Tier mkn: Using Cloud configuration (multi-profile)"
        config_source="config/kilo/kilo-settings-cloud.json"
    elif [ "$TIER" = "pro" ] || [ "$PROFILE" = "pro" ]; then
        print_info "Tier $TIER: Using Pro configuration (multi-profile)"
        config_source="config/kilo/kilo-settings-cloud.json"
    elif [ "$TIER" = "free" ] || [ "$PROFILE" = "ff" ]; then
        print_info "Tier $TIER: Using Free configuration"
        config_source="config/kilo/kilo-settings-free.json"
    elif [ "$enable_external" = "false" ]; then
        print_info "Privacy Mode detected: Using dedicated privacy configuration"
        config_source="config/kilo/kilo-settings-privacy.json"
    else
         print_info "Standard Mode detected: Using standard configuration"
    fi

    if [ -f "$config_source" ]; then
        docker cp "$config_source" "$container_id:/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json"
        print_success "Kilo Code settings copied from $config_source"
        
        # Inject OpenRouter API key if available
        local SDIR="${SECRETS_DIR:-../secrets}"
        if [ -f "$SDIR/openai-api-key.txt" ]; then
            local api_key=$(cat "$SDIR/openai-api-key.txt" 2>/dev/null | tr -d '\n')
            if [ -n "$api_key" ] && [ "$api_key" != "PLACEHOLDER" ]; then
                print_info "Injecting OpenRouter API key..."
                export OPENROUTER_API_KEY="$api_key"
                print_success "OpenRouter API key prepared for Python injection"
            fi
        fi
        
        # Inject Z.ai API key if available
        local zai_key=$(cat "$SDIR/zai-api-key.txt" 2>/dev/null | tr -d '\n')
        if [ -n "$zai_key" ] && [ "$zai_key" != "PLACEHOLDER" ]; then
            print_info "Injecting Z.ai API key..."
            export ZAI_API_KEY="$zai_key"
            print_success "Z.ai API key prepared for Python injection"
        fi
        
        # Overwrite stale Kilo configs in container to prevent merging with old profiles
        print_info "Clearing stale Kilo configs..."
        docker cp "$config_source" "$container_id:/home/workspace-user/config/kilo/kilo-code-settings-ref.json"
        docker cp "$config_source" "$container_id:/home/workspace-user/config/kilo/kilo-settings-hybrid.json"
        docker exec "$container_id" chown workspace-user:workspace-user /home/workspace-user/config/kilo/kilo-code-settings-ref.json
        docker exec "$container_id" chown workspace-user:workspace-user /home/workspace-user/config/kilo/kilo-settings-hybrid.json
        
        # Injection of keys moved to Python block below for safety
        print_success "Stale Kilo configs cleared"
    else
        print_error "Config source $config_source not found"
        # Fallback to standard if specific fails
        if [ -f "config/kilo/kilo-settings-import.json" ]; then
             print_info "Falling back to standard config"
             docker cp "config/kilo/kilo-settings-import.json" "$container_id:/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json"
        fi
    fi
    
    # Create MCP settings
    print_step "Creating MCP settings"
    local SDIR="${SECRETS_DIR:-../secrets}"
    local openrouter_key=$(cat "$SDIR/openai-api-key.txt" 2>/dev/null || echo "placeholder")
    local tavily_key=$(cat "$SDIR/tavily-api-key.txt" 2>/dev/null || echo "placeholder")
    local anthropic_key=$(cat "$SDIR/anthropic-api-key.txt" 2>/dev/null || echo "placeholder")
    local youtube_key=$(cat "$SDIR/youtube-api-key.txt" 2>/dev/null || echo "placeholder")
    
    # Create MCP settings file
    # Priority: use pre-generated config/mcp-config.json (from DMG installer) if it exists
    # This respects the tier-correct config written by build-dmg.sh
    if [ -f "config/mcp-config.json" ] && python3 -c "import json; d=json.load(open('config/mcp-config.json')); assert 'mcpServers' in d and len(d['mcpServers']) >= 5" 2>/dev/null; then
        print_info "Using existing config/mcp-config.json (from installer)"
        cp config/mcp-config.json /tmp/mcp_settings.json
        # Enforce tier filtering — strip Pro-only MCPs from Free tier
        if [ "$TIER" = "free" ]; then
            python3 -c "
import json
with open('/tmp/mcp_settings.json') as f: d = json.load(f)
pro_only = ['ideas-mcp', 'postgres-mcp', 'postgres', 'raindrop-mcp', 'github-mcp', 'kw-extractor-mcp']
for k in pro_only:
    d.get('mcpServers', {}).pop(k, None)
with open('/tmp/mcp_settings.json', 'w') as f: json.dump(d, f, indent=2)
"
            print_info "Free tier: stripped Pro-only MCPs (ideas, postgres, raindrop, github)"
        fi
    elif [ "$TIER" = "pro" ] || [ "$TIER" = "mkn" ] || [ "$PROFILE" = "pro" ]; then
        print_info "Tier $TIER: Generating Pro MCP settings (postgres-mcp, no memory-kg-mcp)..."
        cat > /tmp/mcp_settings.json << EOF
{
  "mcpServers": {
    "gptr-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "gptr-mcp"],
      "env": { "GPTR_MODE": "proxy" },
      "disabled": false,
      "timeout": 900
    },
    "gmail-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "gmail-mcp"],
      "disabled": false,
      "timeout": 900
    },
    "calendar-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "calendar-mcp"],
      "disabled": false,
      "timeout": 900
    },
    "youtube-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "youtube-mcp"],
      "disabled": false,
      "timeout": 900
    },
    "mcp-tasks": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "mcp-tasks"],
      "disabled": false,
      "timeout": 300
    },
    "ideas-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "ideas-mcp"],
      "disabled": false,
      "timeout": 300
    },
    "postgres-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "postgres"],
      "disabled": false,
      "autoApprove": ["query_sql", "execute_sql", "list_tables"]
    },
    "markdownify-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "markdownify-mcp"],
      "disabled": false,
      "timeout": 300
    },
    "tavily-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "tavily-mcp"],
      "disabled": false,
      "timeout": 300
    },
    "kw-extractor-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "kw-extractor-mcp"],
      "disabled": false,
      "timeout": 900,
      "autoApprove": ["kw_extract", "kw_save", "kw_status", "kw_search"]
    }
  }
}
EOF
        # mkn variant: add raindrop-mcp + github-mcp (personal bookmarks + code)
        if [ "$ZOKAI_INSTANCE" = "zokai-mkn" ]; then
            python3 -c "
import json
with open('/tmp/mcp_settings.json') as f: d = json.load(f)
d['mcpServers']['raindrop-mcp'] = {
    'command': 'bash',
    'args': ['/home/workspace-user/scripts/mcp-bridge.sh', 'raindrop-mcp'],
    'disabled': False,
    'timeout': 300
}
d['mcpServers']['github-mcp'] = {
    'command': 'bash',
    'args': ['/home/workspace-user/scripts/mcp-bridge.sh', 'github-mcp'],
    'disabled': False,
    'timeout': 300
}
with open('/tmp/mcp_settings.json', 'w') as f: json.dump(d, f, indent=2)
"
            print_info "mkn: added raindrop-mcp + github-mcp to MCP config"
        fi
    else
        # Standard Configuration (Cloud/Hybrid/Privacy base)
        cat > /tmp/mcp_settings.json << EOF
{
  "mcpServers": {
    "gptr-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "gptr-mcp"],
      "env": { "GPTR_MODE": "proxy" },
      "disabled": false,
      "timeout": 900
    },
    "gmail-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "gmail-mcp"],
      "disabled": false,
      "timeout": 900
    },
    "calendar-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "calendar-mcp"],
      "disabled": false,
      "timeout": 900
    },
    "youtube-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "youtube-mcp"],
      "disabled": false,
      "timeout": 900
    },
    "mcp-tasks": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "mcp-tasks"],
      "disabled": false,
      "timeout": 300
    },
    "ideas-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "ideas-mcp"],
      "disabled": false,
      "timeout": 300
    },
    "postgres-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "postgres"],
      "disabled": false,
      "timeout": 300
    },
    "markdownify-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "markdownify-mcp"],
      "disabled": false,
      "timeout": 300
    },
    "tavily-mcp": {
      "command": "bash",
      "args": ["/home/workspace-user/scripts/mcp-bridge.sh", "tavily-mcp"],
      "disabled": false,
      "timeout": 300
    }
  }
}
EOF
    fi
    
    # mkn variant: add raindrop-mcp (personal bookmarks) — applies to any profile
    if [ "$ZOKAI_INSTANCE" = "zokai-mkn" ]; then
        python3 -c "
import json
with open('/tmp/mcp_settings.json') as f: d = json.load(f)
if 'raindrop-mcp' not in d['mcpServers']:
    d['mcpServers']['raindrop-mcp'] = {
        'command': 'bash',
        'args': ['/home/workspace-user/scripts/mcp-bridge.sh', 'raindrop-mcp'],
        'disabled': False,
        'timeout': 300
    }
if 'github-mcp' not in d['mcpServers']:
    d['mcpServers']['github-mcp'] = {
        'command': 'bash',
        'args': ['/home/workspace-user/scripts/mcp-bridge.sh', 'github-mcp'],
        'disabled': False,
        'timeout': 300
    }
with open('/tmp/mcp_settings.json', 'w') as f: json.dump(d, f, indent=2)
"
        print_info "mkn: added raindrop-mcp + github-mcp to MCP config"
    fi

    # Copy MCP settings to Kilo's settings directory
    docker cp /tmp/mcp_settings.json "$container_id:/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json"
    
    # Also copy to global config location to prevent merging with stale entries
    docker cp /tmp/mcp_settings.json "$container_id:/home/workspace-user/config/mcp-config.json"
    
    rm -f /tmp/mcp_settings.json
    print_success "MCP settings created and copied"
    
    # Set permissions
    docker exec "$container_id" chown -R workspace-user:workspace-user /home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/
    docker exec "$container_id" chown workspace-user:workspace-user /home/workspace-user/config/mcp-config.json
    
    # Update VS Code settings.json to include autoImportSettingsPath
    print_step "Updating VS Code settings.json"
    docker exec -e ENABLE_EXTERNAL_TOOLS="$ENABLE_EXTERNAL_TOOLS" -e LLM_MODEL="$LLM_MODEL" -e OPENROUTER_API_KEY="$api_key" -e ZAI_API_KEY="$zai_key" "$container_id" python3 -c "
import json
import os

settings_path = '/home/workspace-user/.local/share/code-server/User/settings.json'
config_path = '/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json'

try:
    # --- STEP 1: Update Kilo Config (config.json) for Docker Networking & Model ---
    print(f'Updating Kilo config at {config_path}...')
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            try:
                kilo_data = json.load(f)
            except json.JSONDecodeError:
                kilo_data = {}
        
        # --- NEW: Safe API Key Injection (into ALL profiles) ---
        openrouter_key = os.environ.get('OPENROUTER_API_KEY')
        if openrouter_key and openrouter_key != 'PLACEHOLDER':
            print('Safely injecting OpenRouter API key into ALL config profiles...')
            if 'providerProfiles' not in kilo_data:
                kilo_data['providerProfiles'] = {}
            if 'apiConfigs' not in kilo_data['providerProfiles']:
                kilo_data['providerProfiles']['apiConfigs'] = {}
            # Inject into every profile, not just 'default'
            for profile_name in list(kilo_data['providerProfiles']['apiConfigs'].keys()):
                profile = kilo_data['providerProfiles']['apiConfigs'][profile_name]
                if isinstance(profile, dict):
                    profile['openRouterApiKey'] = openrouter_key
                    print(f'  Injected key into profile: {profile_name}')
            # Also ensure 'default' exists
            if 'default' not in kilo_data['providerProfiles']['apiConfigs']:
                kilo_data['providerProfiles']['apiConfigs']['default'] = {}
            kilo_data['providerProfiles']['apiConfigs']['default']['openRouterApiKey'] = openrouter_key
            
        # --- Z.ai API Key Injection (into all zai profiles) ---
        zai_key = os.environ.get('ZAI_API_KEY')
        if zai_key and zai_key != 'PLACEHOLDER':
            print('Injecting Z.ai API key into all zai profiles...')
            for profile_name in list(kilo_data['providerProfiles']['apiConfigs'].keys()):
                profile = kilo_data['providerProfiles']['apiConfigs'][profile_name]
                if isinstance(profile, dict) and profile.get('apiProvider') == 'zai':
                    profile['zaiApiKey'] = zai_key
                    print(f'  Injected Z.ai key into profile: {profile_name}')
            
        # Ensure hierarchy exists
        if 'globalSettings' not in kilo_data:
            kilo_data['globalSettings'] = {}
        if 'codebaseIndexConfig' not in kilo_data['globalSettings']:
            kilo_data['globalSettings']['codebaseIndexConfig'] = {}
            
        # FORCE Docker URLs for codebase index (FastEmbed embedding-server)
        kilo_data['globalSettings']['codebaseIndexConfig']['codebaseIndexEmbedderBaseUrl'] = 'http://embedding-server:7997'
        kilo_data['globalSettings']['codebaseIndexConfig']['codebaseIndexQdrantUrl'] = 'http://qdrant:6333'
        kilo_data['globalSettings']['codebaseIndexConfig']['codebaseIndexOpenAiCompatibleBaseUrl'] = 'http://embedding-server:7997/v1'
        kilo_data['globalSettings']['codebaseIndexConfig']['codebaseIndexEmbedderModelId'] = 'sentence-transformers/paraphrase-multilingual-mpnet-base-v2'
        kilo_data['globalSettings']['codebaseIndexConfig']['codebaseIndexEmbedderModelDimension'] = 768
        kilo_data['globalSettings']['codebaseIndexConfig']['codebaseIndexEmbedderProvider'] = 'openai-compatible'
        kilo_data['globalSettings']['codebaseIndexConfig']['codebaseIndexEnabled'] = True
        
            # Inject Model ID from Env if present
        llm_model = os.environ.get('LLM_MODEL')
        if llm_model:
            print(f'Injecting Model ID: {llm_model}')
            # Navigate to providerProfiles -> apiConfigs -> default -> apiModelId
            if 'providerProfiles' not in kilo_data:
                kilo_data['providerProfiles'] = {}
            if 'apiConfigs' not in kilo_data['providerProfiles']:
                kilo_data['providerProfiles']['apiConfigs'] = {}
            if 'default' not in kilo_data['providerProfiles']['apiConfigs']:
                kilo_data['providerProfiles']['apiConfigs']['default'] = {}
                
            # FORCE the active profile to be 'default' to ensure we use this config
            kilo_data['providerProfiles']['currentApiConfigName'] = 'default'
            
            # Update the default profile
            kilo_data['providerProfiles']['apiConfigs']['default']['apiModelId'] = llm_model
            
            # Ensure provider is LM Studio (Critical for Privacy Mode)
            kilo_data['providerProfiles']['apiConfigs']['default']['apiProvider'] = 'lmstudio'
            # Force Base URL for Docker networking (Localhost in container != Localhost on host)
            kilo_data['providerProfiles']['apiConfigs']['default']['apiBaseUrl'] = 'http://host.docker.internal:1234/v1'
            
            # --- CLEANUP: Keys are now preserved to satisfy strict schema validation ---
            # (Previously removed, but caused auto-import failures)
            
            # --- CRITICAL: Update ALL Modes to use the Default Profile ID ---
            # Retrieve the ID of the default profile
            default_id = kilo_data['providerProfiles']['apiConfigs']['default'].get('id')
            if default_id and 'modeApiConfigs' in kilo_data['providerProfiles']:
                print(f'Updating all Kilo modes to use default profile ID: {default_id}')
                for mode_key in kilo_data['providerProfiles']['modeApiConfigs']:
                    kilo_data['providerProfiles']['modeApiConfigs'][mode_key] = default_id
            else:
                 print('Warning: Could not enable all modes for local LLM (missing default ID or modeApiConfigs).')
        
        with open(config_path, 'w') as f:
            json.dump(kilo_data, f, indent=4)
        print('Successfully enforced Docker URLs in Kilo config (Embedding: http://embedding-server:7997, Qdrant: http://qdrant:6333)')
    else:
        print('Warning: config.json not found, skipping URL update.')

    # --- STEP 1.1: Inject Key into secondary config files ---
    for path in ['/home/workspace-user/config/kilo/kilo-code-settings-ref.json', '/home/workspace-user/config/kilo/kilo-settings-hybrid.json']:
        if os.path.exists(path):
            print(f'Injecting key into {path}...')
            with open(path, 'r') as f:
                try: data = json.load(f)
                except: data = {}
            
            openrouter_key = os.environ.get('OPENROUTER_API_KEY')
            if openrouter_key and openrouter_key != 'PLACEHOLDER':
                if 'providerProfiles' not in data:
                    data['providerProfiles'] = {}
                if 'apiConfigs' not in data['providerProfiles']:
                    data['providerProfiles']['apiConfigs'] = {}
                # Inject into ALL profiles
                for pname in list(data['providerProfiles']['apiConfigs'].keys()):
                    p = data['providerProfiles']['apiConfigs'][pname]
                    if isinstance(p, dict):
                        p['openRouterApiKey'] = openrouter_key
                if 'default' not in data['providerProfiles']['apiConfigs']:
                    data['providerProfiles']['apiConfigs']['default'] = {}
                data['providerProfiles']['apiConfigs']['default']['openRouterApiKey'] = openrouter_key
                with open(path, 'w') as f:
                    json.dump(data, f, indent=4)

    # --- STEP 1.5: Disable External Tools if Privacy Mode ---
    enable_external = os.environ.get('ENABLE_EXTERNAL_TOOLS', 'true').lower() == 'true'
    mcp_path = '/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json'
    
    if not enable_external:
        print(f'Privacy Mode: Disabling external MCP tools in {mcp_path}...')
        if os.path.exists(mcp_path):
            with open(mcp_path, 'r') as f:
                try: 
                    mcp_data = json.load(f)
                except: 
                    mcp_data = {}
            
            servers = mcp_data.get('mcpServers', {})
            # List of tools to disable in Privacy Mode
            tools_to_disable = ['youtube-mcp', 'gmail-mcp', 'calendar-mcp', 'github-mcp', 'raindrop-mcp', 'gptr-mcp', 'crawl4ai-mcp']
            
            for tool in tools_to_disable:
                if tool in servers:
                    del servers[tool]
                    print(f'  -> Removed {tool} from configuration')
            
            with open(mcp_path, 'w') as f:
                json.dump(mcp_data, f, indent=4)
            print('Successfully disabled external tools.')

    # --- STEP 2: Link Config in VS Code Settings ---
    if os.path.exists(settings_path):
        with open(settings_path, 'r') as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                data = {}
    else:
        data = {}

    data['kilo-code.autoImportSettingsPath'] = config_path

    with open(settings_path, 'w') as f:
        json.dump(data, f, indent=4)
        
    print('Successfully updated settings.json')
except Exception as e:
    print(f'Error updating configuration: {e}')
    exit(1)
"
    if [ $? -eq 0 ]; then
        print_success "VS Code settings updated"
    else
        print_error "Failed to update VS Code settings"
    fi
    
    # Create Documents directory and symlink youtube_output (Kilo Code expectation)
    print_step "Configuring Documents link"
    docker exec "$container_id" mkdir -p /home/workspace-user/Documents
    docker exec "$container_id" ln -sf /home/workspace-user/youtube_output /home/workspace-user/Documents/youtube_output
    docker exec "$container_id" chown -R workspace-user:workspace-user /home/workspace-user/Documents
    print_success "Documents configuration complete"

    print_success "Kilo Code configuration completed"
    print_info "Please restart VS Code to apply the settings"
}

# Run main function
main "$@"