#!/bin/bash
# Zokai™ Station Installer
# Unified installer for all tiers: free, pro, mkn

set -e

# --- Constants & Configuration ---
VERSION="3.0.0"
LOG_FILE="install.log"
CONFIG_DIR="config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# State Variables
INTERACTIVE=false # Always non-interactive
DRY_RUN=false
GPU_ENABLED=false
DEV_MODE=false     # --dev: debug overlay (extra ports, verbose logging)
AUTO_MODE=false    # --auto: skip all interactive prompts, reuse existing keys
TIER=""            # free|pro|mkn — set via --tier or auto-detected
LLM_MODE="cloud"   # cloud|local|hybrid — set via --llm-mode flag

# --- Argument Parsing ---

show_help() {
    cat <<EOF
Zokai™ Station Installer v$VERSION

Usage: ./installer.sh [OPTIONS]

Options:
  --tier <TIER>     Tier: free, pro, mkn (auto-detected if omitted)
  --llm-mode <MODE> LLM mode: cloud (default), local, hybrid
  --dev             Developer overlay (debug ports, verbose logging)
  --auto            Skip all interactive prompts, reuse existing API keys
  --update          Update existing installation (preserves data)
  --dry-run         Generate config only, do not start Docker
  --help            Show this help message

Tier determines which services run:
  free   Core + free MCPs (port 8081, ZokaiData-free/)
  pro    Free + postgres + gap-indexer (port 8082, ZokaiData-pro/)
  mkn    Pro + raindrop-mcp (port 8080, ZokaiData/)

Tier auto-detection:
  1. Existing TIER= in .env
  2. docker-compose.pro.yml present → pro
  3. Otherwise → free
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tier)
                TIER="$2"
                shift 2
                ;;
            --llm-mode)
                LLM_MODE="$2"
                shift 2
                ;;
            --dev)
                DEV_MODE=true
                shift
                ;;
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --update)
                UPDATE_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# --- Helper Functions ---

log() {
    local level=$1
    shift
    local msg="$*"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
}

print_step() {
    echo -e "${BLUE}==>${NC} $1"
    log "INFO" "STEP: $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    log "INFO" "SUCCESS: $1"
}

print_error() {
    echo -e "${RED}Error:${NC} $1"
    log "ERROR" "$1"
}

print_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
    log "WARN" "$1"
}

print_info() {
    echo -e "${NC}--> $1"
    log "INFO" "$1"
}

# Install host-side URL watcher as a macOS launchd agent so it
# auto-starts on login and survives reboots (fixes H40 / Lesson #65).
#
# Strategy by tier:
#   free  — file-based watcher: scripts/ is a LOCAL path, launchd can read it.
#   pro / mkn — docker exec watcher: scripts/ is on Google Drive (FUSE),
#               which launchd agents cannot access without Full Disk Access.
#               Instead we read the queue file directly from inside the container
#               using `docker exec`, bypassing FUSE entirely (H65).
#
# Each tier uses a unique label (ai.zokai.url-watcher.$ZOKAI_INSTANCE) so
# Free / Pro / MKN agents coexist without overwriting each other.
install_url_watcher_launchd() {
    if [[ "$OSTYPE" != darwin* ]]; then return; fi

    local instance="${ZOKAI_INSTANCE:-zokai-free}"
    local agent_label="ai.zokai.url-watcher.${instance}"
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist_path="$plist_dir/${agent_label}.plist"
    local log_file="/tmp/zokai-url-watcher-${instance}.log"
    local scripts_home="$HOME/Library/Scripts/zokai"
    mkdir -p "$plist_dir" "$scripts_home"

    local watcher_path   # path launchd will exec (always local, never GDrive)

    if [ "$TIER" = "free" ]; then
        # Free tier: scripts/ lives at a local path — use the existing file-based watcher.
        local script_dir
        script_dir="$(cd "$(dirname "$0")" && pwd)"
        local file_watcher="$script_dir/scripts/open-url-watcher.sh"
        if [ ! -f "$file_watcher" ]; then
            print_warning "open-url-watcher.sh not found — skipping launchd registration"
            return
        fi
        watcher_path="$(cd "$script_dir/scripts" && pwd)/open-url-watcher.sh"
        chmod +x "$watcher_path"
    else
        # Pro / MKN tier: scripts/ is on Google Drive (FUSE).
        # Generate a local docker exec watcher so launchd never touches GDrive.
        local vs_container="${instance}-vs-code"
        local queue_in_container="/home/workspace-user/scripts/.open-url-queue"
        watcher_path="$scripts_home/url-watcher-${instance}.sh"

        cat > "$watcher_path" <<WATCHER
#!/bin/bash
# Zokai ${instance} — URL relay watcher (docker exec, generated by installer)
# Reads the relay queue directly from inside the container — no FUSE/TCC issues.
CONTAINER="${vs_container}"
QUEUE="${queue_in_container}"
DOCKER="/usr/local/bin/docker"

echo "[url-watcher-${instance}] Watching via docker exec (\$CONTAINER)..."
while true; do
    URL=\$("\$DOCKER" exec "\$CONTAINER" cat "\$QUEUE" 2>/dev/null)
    if [ -n "\$URL" ]; then
        "\$DOCKER" exec "\$CONTAINER" bash -c "> \$QUEUE" 2>/dev/null
        echo "[url-watcher-${instance}] Opening: \$URL"
        /usr/bin/open "\$URL"
    fi
    sleep 1
done
WATCHER
        chmod +x "$watcher_path"
        print_info "URL watcher script (docker exec): $watcher_path"
    fi

    cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${agent_label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${watcher_path}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${log_file}</string>
    <key>StandardErrorPath</key>
    <string>${log_file}</string>
</dict>
</plist>
PLIST

    launchctl unload "$plist_path" 2>/dev/null || true
    launchctl load "$plist_path"
    print_success "URL watcher registered: ${agent_label} (auto-starts on login)"
}


# Safe .env loader: Docker Compose .env files must NOT quote values (H41),
# but bash `source` word-splits unquoted values with spaces (e.g. paths with
# spaces in directory names). This function reads each KEY=VALUE line and exports it
# with proper quoting so bash doesn't break on spaces.
safe_source_env() {
    local envfile="$1"
    [ -f "$envfile" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        # Extract key (everything before first =) and value (everything after)
        local key="${line%%=*}"
        local val="${line#*=}"
        # Strip surrounding quotes if present (some .env files quote values)
        val="${val#\"}"; val="${val%\"}"
        val="${val#\'}"; val="${val%\'}"
        export "$key=$val"
    done < "$envfile"
}

ENV_FILE=""  # set per-tier in derive_tier_config() — e.g. .env.free, .env.mkn

update_env_var() {
    local key=$1
    local val=$2
    # Docker Compose .env files treat quotes as literal characters (H41).
    # Do NOT wrap values in quotes — they become part of the value.
    if grep -q "^$key=" "$ENV_FILE"; then
        # Use temp file + cp instead of sed -i (sed -i fails on FUSE/Google Drive)
        local tmpfile="/tmp/.env_update_$$"
        sed "s|^$key=.*|$key=$val|" "$ENV_FILE" > "$tmpfile"
        cp "$tmpfile" "$ENV_FILE"
        rm -f "$tmpfile"
    else
        echo "$key=$val" >> "$ENV_FILE"
    fi
}


# --- Core Logic ---

check_prerequisites() {
    print_step "Checking Prerequisites"
    
    # Docker Check
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed."
        exit 1
    fi

    # GPU Check (Simplified)
    if command -v nvidia-smi &> /dev/null; then
        print_success "NVIDIA GPU detected"
        GPU_ENABLED=true
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if system_profiler SPHardwareDataType | grep -q "Chip: Apple"; then
             print_success "Apple Silicon detected"
             GPU_ENABLED=true
        fi
    fi
}

# --- Secrets Directory Setup ---
# Secrets live in DATA_DIR/secrets (persistent, survives code updates).
# SECRETS_DIR is set after DATA_DIR is resolved (see main flow).

setup_secrets_dir() {
    SECRETS_DIR="${SECRETS_DIR:-$DATA_DIR/secrets}"
    mkdir -p "$SECRETS_DIR"

    # Migration: if core/secrets/ has real keys, copy them to SECRETS_DIR
    if [ -d "secrets" ] && [ "$SECRETS_DIR" != "secrets" ] && [ "$SECRETS_DIR" != "./secrets" ]; then
        local migrated=false
        for f in secrets/*.txt secrets/*.json; do
            [ -f "$f" ] || continue
            local basename=$(basename "$f")
            local target="$SECRETS_DIR/$basename"
            # Only migrate if target doesn't exist or is empty/placeholder
            if [ ! -f "$target" ] || echo "$(cat "$target" 2>/dev/null)" | grep -qi '^placeholder$' || [ -z "$(cat "$target" 2>/dev/null)" ]; then
                local content=$(cat "$f" 2>/dev/null)
                if [ -n "$content" ] && ! echo "$content" | grep -qi '^placeholder$'; then
                    cp "$f" "$target"
                    migrated=true
                fi
            fi
        done
        if [ "$migrated" = true ]; then
            print_success "Migrated secrets from core/secrets/ → $SECRETS_DIR"
        fi
    fi

    # Ensure all 13 placeholder files exist (bind mount boot trap — retro 2026-02-01)
    for secret_file in openai-api-key.txt openrouter-api-key.txt anthropic-api-key.txt \
                       tavily-api-key.txt google-api-key.txt google-cx.txt \
                       youtube-api-key.txt raindrop-token.txt github-token.txt \
                       supabase-key.txt postgres-password.txt zai-api-key.txt; do
        [ -f "$SECRETS_DIR/$secret_file" ] || echo "" > "$SECRETS_DIR/$secret_file"
    done
    [ -f "$SECRETS_DIR/token.json" ] || echo "{}" > "$SECRETS_DIR/token.json"

    print_success "Secrets directory: $SECRETS_DIR"
}

setup_openrouter_key() {
    print_step "OpenRouter API Key Setup"
    
    # Check if key already exists (in SECRETS_DIR)
    if [ -f "$SECRETS_DIR/openai-api-key.txt" ]; then
        local existing_key=$(cat "$SECRETS_DIR/openai-api-key.txt" 2>/dev/null)
        if [ -n "$existing_key" ] && [ "$existing_key" != "PLACEHOLDER" ]; then
            # --auto: silently accept existing key
            if [ "$AUTO_MODE" = true ]; then
                print_success "Using existing OpenRouter API key (auto)"
                return
            fi
            echo "  Existing API key found."
            read -p "  Use existing key? [Y/n]: " use_existing
            if [ "$use_existing" != "n" ] && [ "$use_existing" != "N" ]; then
                print_success "Using existing OpenRouter API key"
                return
            fi
        fi
    fi
    
    # --auto with no existing key: use PLACEHOLDER
    if [ "$AUTO_MODE" = true ]; then
        print_warning "No existing API key found. Using PLACEHOLDER (auto mode)"
        echo "PLACEHOLDER" > "$SECRETS_DIR/openai-api-key.txt"
        echo "PLACEHOLDER" > "$SECRETS_DIR/openrouter-api-key.txt"
        return
    fi
    
    echo ""
    echo "Zokai Station uses OpenRouter for LLM access (free tier)."
    echo "Get your free API key at: https://openrouter.ai/settings/keys"
    echo ""
    
    # Prompt for new key
    read -p "  Enter your OpenRouter API key: " api_key
    
    if [ -z "$api_key" ]; then
        print_warning "No API key provided. LLM features will not work until a key is added."
        api_key="PLACEHOLDER"
    else
        print_success "OpenRouter API key saved"
    fi
    
    echo "$api_key" > "$SECRETS_DIR/openai-api-key.txt"
    echo "$api_key" > "$SECRETS_DIR/openrouter-api-key.txt"
}

setup_tavily_key() {
    print_step "Tavily API Key Setup (Web Search)"
    
    # Check if key already exists
    if [ -f "$SECRETS_DIR/tavily-api-key.txt" ]; then
        local existing_key=$(cat "$SECRETS_DIR/tavily-api-key.txt" 2>/dev/null)
        if [ -n "$existing_key" ] && [ "$existing_key" != "PLACEHOLDER" ] && [ "$existing_key" != "" ]; then
            # --auto: silently accept existing key
            if [ "$AUTO_MODE" = true ]; then
                print_success "Using existing Tavily API key (auto)"
                return
            fi
            echo "  Existing Tavily API key found."
            read -p "  Use existing key? [Y/n]: " use_existing
            if [ "$use_existing" != "n" ] && [ "$use_existing" != "N" ]; then
                print_success "Using existing Tavily API key"
                return
            fi
        fi
    fi
    
    # --auto with no existing key: use PLACEHOLDER
    if [ "$AUTO_MODE" = true ]; then
        print_info "No Tavily key → DuckDuckGo fallback (keyless)"
        echo "PLACEHOLDER" > "$SECRETS_DIR/tavily-api-key.txt"
        return
    fi
    
    echo ""
    echo "Tavily improves web search quality (optional — DuckDuckGo used as fallback)."
    echo "Get your free API key at: https://tavily.com (1000 free searches/month)"
    echo ""
    
    # Prompt for new key
    read -p "  Enter your Tavily API key (press Enter to skip): " tavily_key
    
    if [ -z "$tavily_key" ]; then
        print_info "Skipped — using DuckDuckGo for web search (no key needed)"
        print_info "You can add Tavily later: echo 'YOUR_KEY' > $SECRETS_DIR/tavily-api-key.txt"
        tavily_key="PLACEHOLDER"
    else
        print_success "Tavily API key saved"
    fi
    
    echo "$tavily_key" > "$SECRETS_DIR/tavily-api-key.txt"
    # Bridge secret propagation: copy key into scripts volume so the
    # mcp_bridge.py host_secret_env fallback can find it inside vs-code container.
    # (The tavily secret is NOT in the vs-code container's /run/secrets mount.)
    if [ -n "$DATA_DIR" ] && [ -d "$DATA_DIR/scripts" ]; then
        echo "$tavily_key" > "$DATA_DIR/scripts/.tavily-api-key"
        chmod 600 "$DATA_DIR/scripts/.tavily-api-key" 2>/dev/null || true
    fi
}

# Detect Tavily key → set RETRIEVER accordingly
setup_retriever() {
    local tavily_key=$(cat "$SECRETS_DIR/tavily-api-key.txt" 2>/dev/null)
    if [ -n "$tavily_key" ] && ! echo "$tavily_key" | grep -qi '^placeholder$' && [ "$tavily_key" != "" ]; then
        update_env_var "RETRIEVER" "tavily"
        print_success "Web search: Tavily (API key detected)"
    else
        update_env_var "RETRIEVER" "duckduckgo"
        print_info "Web search: DuckDuckGo (keyless fallback)"
    fi
}

configure_scenario() {
    print_step "Configuring Scenario (TIER=$TIER, LLM_MODE=$LLM_MODE)"

    # Provider defaults based on LLM_MODE
    case "$LLM_MODE" in
        cloud)
            LLM_PROVIDER="openrouter"
            ENABLE_EXTERNAL_TOOLS=true
            ;;
        local)
            LLM_PROVIDER="ollama"
            ENABLE_EXTERNAL_TOOLS=false
            ;;
        hybrid)
            LLM_PROVIDER="openrouter"
            ENABLE_EXTERNAL_TOOLS=true
            ;;
        *)
            print_error "Unknown LLM_MODE: $LLM_MODE (expected: cloud, local, hybrid)"
            exit 1
            ;;
    esac

    LLM_API_BASE=""
    
    echo "  - TIER: $TIER"
    echo "  - LLM Mode: $LLM_MODE (provider: $LLM_PROVIDER)"
    echo "  - Indexing: Local (FastEmbed)"
    echo "  - Tools: $([ "$ENABLE_EXTERNAL_TOOLS" = true ] && echo 'Enabled' || echo 'Disabled')"

    # Export to .env
    touch "$ENV_FILE"
    update_env_var "LLM_PROVIDER" "$LLM_PROVIDER"

    update_env_var "ENABLE_EXTERNAL_TOOLS" "$ENABLE_EXTERNAL_TOOLS"
    update_env_var "TIER" "$TIER"
    update_env_var "LLM_MODE" "$LLM_MODE"
    # Backward compat: keep PROFILE for any scripts that still read it
    case "$TIER" in
        free) update_env_var "PROFILE" "ff" ;;
        pro)  update_env_var "PROFILE" "pro" ;;
        mkn)  update_env_var "PROFILE" "hybrid" ;;
    esac
    
    # Clear YouTube API key (keyless mode - transcription only)
    echo "" > "$SECRETS_DIR/youtube-api-key.txt"
    echo "  - YouTube MCP: Keyless mode (transcription only)"

    # Export variables for Python script / configure scripts
    export LLM_PROVIDER
    export LLM_MODEL="" # Will be picked up from JSON defaults
    export ENABLE_EXTERNAL_TOOLS
    export ZAI_REGION="international"
    export API_KEY="" # No key by default

    # Select base Kilo settings file based on LLM_MODE
    print_step "Preparing Kilo Configuration..."
    local kilo_template="config/kilo/kilo-settings-${LLM_MODE}.json"
    # Fallback: try cloud-ff for backward compat
    if [ ! -f "$kilo_template" ] && [ -f "config/kilo/kilo-settings-cloud-ff.json" ]; then
        kilo_template="config/kilo/kilo-settings-cloud-ff.json"
    fi
    if [ -f "$kilo_template" ]; then
        cp "$kilo_template" "config/kilo/kilo-settings-import.json"
        cp "$kilo_template" "config/kilo-settings.json"
        print_info "Using Kilo settings template: $(basename "$kilo_template")"
    else
        print_error "$kilo_template not found!"
        exit 1
    fi

    # --- Pin Kilo Code VSIX (WO-KILO-1) ---
    local KILO_VERSION="5.9.0"
    local KILO_VSIX_SHA256="d411c08e838097cf845f74689e66abe44907410c4fda2d9c6a472168cb5a45b4"
    local KILO_VSIX_PATH="config/kilo_code.vsix"

    if [ ! -f "$KILO_VSIX_PATH" ]; then
        print_step "Downloading Kilo Code v${KILO_VERSION}..."
        curl -L "https://open-vsx.org/api/kilocode/kilo-code/${KILO_VERSION}/file/kilocode.kilo-code-${KILO_VERSION}.vsix" \
             -o "$KILO_VSIX_PATH" --fail --silent --show-error
        if [ $? -ne 0 ]; then
            print_error "Failed to download Kilo Code VSIX from Open VSX"
            rm -f "$KILO_VSIX_PATH"
            exit 1
        fi
        # SHA256 verification
        local ACTUAL_SHA
        if command -v shasum &>/dev/null; then
            ACTUAL_SHA=$(shasum -a 256 "$KILO_VSIX_PATH" | awk '{print $1}')
        else
            ACTUAL_SHA=$(sha256sum "$KILO_VSIX_PATH" | awk '{print $1}')
        fi
        if [ "$ACTUAL_SHA" != "$KILO_VSIX_SHA256" ]; then
            print_error "VSIX SHA256 mismatch! Expected: $KILO_VSIX_SHA256, Got: $ACTUAL_SHA"
            rm -f "$KILO_VSIX_PATH"
            exit 1
        fi
        print_success "Kilo Code v${KILO_VERSION} downloaded (SHA256 verified)"
    else
        print_info "Kilo Code VSIX already present (v${KILO_VERSION})"
    fi
}

start_services() {
    print_step "Starting Services (TIER=$TIER)"

    local compose_cmd="docker compose"
    if ! command -v docker-compose &> /dev/null; then
        if ! docker compose version &> /dev/null; then
            print_error "Docker Compose not found."
            exit 1
        fi
    fi

    # --- Build compose file list ---
    local compose_files="-f docker-compose.yml"

    # Pro overlay (pro and mkn tiers)
    if [ "$TIER" = "pro" ] || [ "$TIER" = "mkn" ]; then
        local pro_overlay=""
        if [ -f docker-compose.pro.yml ]; then
            pro_overlay="docker-compose.pro.yml"
        elif [ -f ../docker-compose.pro.yml ]; then
            pro_overlay="../docker-compose.pro.yml"
        fi
        if [ -n "$pro_overlay" ]; then
            compose_files+=" -f $pro_overlay"
            print_info "Pro overlay: $pro_overlay"
        fi
    fi

    # Dev mode overlay
    if [ "$DEV_MODE" = true ]; then
        compose_files+=' -f docker-compose.dev.yml'
        print_info "Dev overlay: docker-compose.dev.yml"
    fi

    # --- Service lists by tier ---
    local core_services="vs-code nginx-proxy secrets-manager workspace-manager config-service service-discovery qdrant redis embedding-server"
    local base_mcps="ingestor gptr-mcp gmail-mcp calendar-mcp youtube-mcp mcp-tasks markdownify-mcp tavily-mcp"
    local pro_services=""
    local tier_services=""

    case "$TIER" in
        free)
            # Free: core + base MCPs (memory-kg-mcp is a volume mount, not a compose service)
            tier_services=""
            ;;
        pro)
            # Pro: core + base MCPs + postgres + gap-indexer
            pro_services="postgres-db postgres-mcp gap-indexer"
            ;;
        mkn)
            # mkn: Pro + raindrop-mcp
            pro_services="postgres-db postgres-mcp gap-indexer"
            tier_services="raindrop-mcp"
            ;;
    esac

    if [ -n "$pro_services" ]; then
        print_info "Pro services: $pro_services"
    fi
    if [ -n "$tier_services" ]; then
        print_info "Tier-specific services: $tier_services"
    fi

    local cmd="$compose_cmd --env-file $ENV_FILE $compose_files up -d --remove-orphans $core_services $base_mcps $pro_services $tier_services"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY RUN] Executing: $cmd"
    else
        eval "$cmd"
        print_success "Services started (TIER=$TIER)"

        # launchd watcher: only on prod (not dev) — dev has no persistent agent
        if [ "$DEV_MODE" != true ]; then
            install_url_watcher_launchd
        fi

        # Clean stale codebase index on UPDATE to prevent duplicates.
        # Kilo's indexing state lives inside the VS Code container (not Qdrant).
        # Container recreation wipes that state, so Kilo re-indexes from scratch
        # with new point IDs — duplicating every vector in the existing collection.
        # Email/calendar collections use deterministic UUIDs and are safe.
        if [ "$UPDATE_MODE" = true ]; then
            print_step "Cleaning stale codebase index..."
            local qdrant_container=$(docker ps --filter "name=${ZOKAI_INSTANCE}-qdrant" --format '{{.ID}}' | head -1)
            if [ -n "$qdrant_container" ]; then
                # Wait for Qdrant to be ready (health check may still be starting)
                local retries=0
                while [ $retries -lt 10 ]; do
                    if docker exec "$qdrant_container" wget -q -O - http://localhost:6333/collections >/dev/null 2>&1; then
                        break
                    fi
                    retries=$((retries + 1))
                    sleep 1
                done
                # Delete all ws-* collections (codebase index)
                local ws_collections=$(docker exec "$qdrant_container" wget -q -O - http://localhost:6333/collections 2>/dev/null \
                    | python3 -c "import sys,json; [print(c['name']) for c in json.load(sys.stdin).get('result',{}).get('collections',[]) if c['name'].startswith('ws-')]" 2>/dev/null)
                if [ -n "$ws_collections" ]; then
                    for col in $ws_collections; do
                        docker exec "$qdrant_container" wget -q -O - --method=DELETE "http://localhost:6333/collections/$col" >/dev/null 2>&1
                        print_info "Deleted stale codebase index: $col"
                    done
                    print_success "Codebase index cleaned (Kilo will re-index fresh)"
                else
                    print_info "No stale codebase index found"
                fi
            fi
        fi

        # Auto-configure Kilo Code
        print_step "Auto-configuring Kilo Code..."
        export TIER
        export LLM_MODE
        export ZOKAI_INSTANCE
        # Backward compat: configure-kilo-code.sh still reads PROFILE
        case "$TIER" in
            free) export PROFILE="ff" ;;
            pro)  export PROFILE="pro" ;;
            mkn)  export PROFILE="hybrid" ;;
        esac
        ./scripts/configure-kilo-code.sh

        # Pro/mkn tier: run KW Pro installer (SQL migration, commands, customInstructions swap)
        if [ "$TIER" = "pro" ] || [ "$TIER" = "mkn" ]; then
            print_step "Installing Knowledge Weaver Pro..."
            local pro_script_dir="$(cd "$(dirname "$0")" && pwd)"
            local kw_pro_installer="$pro_script_dir/../pro/install_kw_pro.sh"
            if [ -f "$kw_pro_installer" ]; then
                ZOKAI_INSTANCE="$ZOKAI_INSTANCE" bash "$kw_pro_installer"
            else
                print_warning "KW Pro installer not found at $kw_pro_installer — skipping"
            fi

            # Seed AOF shared memory files (Pro/MKN only)
            print_step "Seeding Agent Shared Memory..."
            local vs_container=$(docker ps --filter "name=${ZOKAI_INSTANCE}-vs-code" --format '{{.ID}}' | head -1)
            if [ -n "$vs_container" ]; then
                docker exec "$vs_container" bash -c '
                    mkdir -p /home/workspace-user/workspaces/.kilo/shared
                    mkdir -p /home/workspace-user/workspaces/.kilo/rules-orchestrator

                    # Shared memory files (only create if missing)
                    for f in active_research open_questions decisions; do
                        target="/home/workspace-user/workspaces/.kilo/shared/${f}.md"
                        if [ ! -f "$target" ]; then
                            echo "---" > "$target"
                            echo "title: ${f}" >> "$target"
                            echo "type: shared-memory" >> "$target"
                            echo "---" >> "$target"
                            echo "" >> "$target"
                            echo "# ${f}" >> "$target"
                            echo "" >> "$target"
                            echo "> AOF shared memory — agents read and write this file during multi-agent workflows." >> "$target"
                        fi
                    done
                    chown -R workspace-user:workspace-user /home/workspace-user/workspaces/.kilo/shared/ 2>/dev/null
                ' && print_success "Shared memory seeded (.kilo/shared/)" || print_warning "Could not seed shared memory"

                # Orchestrator routing rules (only create if missing)
                if [ -f "config/kilo/orchestrator-routing.md" ]; then
                    docker cp "config/kilo/orchestrator-routing.md" "$vs_container:/home/workspace-user/workspaces/.kilo/rules-orchestrator/routing.md"
                    print_success "Orchestrator routing rules installed"
                fi
            fi
        fi
    fi
}

# --- Main Execution ---

# --- Tier Resolution ---
# Called after .env is sourced, before services start
resolve_tier() {
    # If --tier was passed, validate it
    if [ -n "$TIER" ]; then
        case "$TIER" in
            free|pro|mkn) ;; # valid
            *)
                print_error "Invalid tier: $TIER (expected: free, pro, mkn)"
                exit 1
                ;;
        esac
        print_info "Tier: $TIER (from --tier flag)"
        return
    fi

    # Auto-detect from existing .env
    if [ -n "$(grep '^TIER=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"')" ]; then
        TIER=$(grep '^TIER=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')
        print_info "Tier: $TIER (from existing .env)"
        return
    fi

    # Auto-detect from ZOKAI_INSTANCE in existing .env
    local existing_instance=$(grep '^ZOKAI_INSTANCE=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"')
    case "$existing_instance" in
        zokai-mkn) TIER="mkn" ;;
        zokai-pro) TIER="pro" ;;
        zokai-free) TIER="free" ;;
        zokai-dev) TIER="free" ;; # dev was always free-based
    esac
    if [ -n "$TIER" ]; then
        print_info "Tier: $TIER (from existing ZOKAI_INSTANCE=$existing_instance)"
        return
    fi

    # Auto-detect from docker-compose.pro.yml presence
    if [ -f docker-compose.pro.yml ] || [ -f ../docker-compose.pro.yml ]; then
        TIER="pro"
        print_info "Tier: pro (docker-compose.pro.yml detected)"
        return
    fi

    # Default
    TIER="free"
    print_info "Tier: free (default)"
}

# Derive ZOKAI_INSTANCE, port, and DATA_DIR from TIER
derive_tier_config() {
    local port_offset=0
    case "$TIER" in
        free)
            ZOKAI_INSTANCE="zokai-free"
            VSCODE_PORT=8081
            DATA_DIR="${DATA_DIR:-$HOME/Documents/ZokaiData-free}"
            SUBNET_FRONTEND="172.31.0.0/16"; GW_FRONTEND="172.31.0.1"
            SUBNET_BACKEND="172.32.0.0/16";  GW_BACKEND="172.32.0.1"
            SUBNET_DATA="172.33.0.0/16";     GW_DATA="172.33.0.1"
            SUBNET_MGMT="172.34.0.0/16";     GW_MGMT="172.34.0.1"
            port_offset=100
            ;;
        pro)
            ZOKAI_INSTANCE="zokai-pro"
            VSCODE_PORT=8082
            DATA_DIR="${DATA_DIR:-$HOME/Documents/ZokaiData-pro}"
            SUBNET_FRONTEND="172.41.0.0/16"; GW_FRONTEND="172.41.0.1"
            SUBNET_BACKEND="172.42.0.0/16";  GW_BACKEND="172.42.0.1"
            SUBNET_DATA="172.43.0.0/16";     GW_DATA="172.43.0.1"
            SUBNET_MGMT="172.44.0.0/16";     GW_MGMT="172.44.0.1"
            port_offset=200
            ;;
        mkn)
            ZOKAI_INSTANCE="zokai-mkn"
            VSCODE_PORT=8080
            DATA_DIR="${DATA_DIR:-$HOME/Documents/ZokaiData}"
            SUBNET_FRONTEND="172.21.0.0/16"; GW_FRONTEND="172.21.0.1"
            SUBNET_BACKEND="172.22.0.0/16";  GW_BACKEND="172.22.0.1"
            SUBNET_DATA="172.23.0.0/16";     GW_DATA="172.23.0.1"
            SUBNET_MGMT="172.24.0.0/16";     GW_MGMT="172.24.0.1"
            port_offset=0
            ;;
    esac

    # Derive service ports from offset (mkn=0, free=+100, pro=+200)
    NGINX_HTTP_PORT=$((80 + port_offset))
    NGINX_HTTPS_PORT=$((443 + port_offset))
    GMAIL_MCP_PORT=$((8007 + port_offset))
    GMAIL_DASHBOARD_PORT=$((8017 + port_offset))
    CALENDAR_MCP_PORT=$((8008 + port_offset))
    CALENDAR_DASHBOARD_PORT=$((8018 + port_offset))
    QDRANT_PORT=$((16333 + port_offset))
    QDRANT_GRPC_PORT=$((16334 + port_offset))
    REDIS_PORT=$((6379 + port_offset))
    POSTGRES_PORT=$((54322 + port_offset))
    WORKSPACE_MGR_PORT=$((9000 + port_offset))
    SECRETS_MGR_PORT=$((9001 + port_offset))
    OAUTH_CALLBACK_PORT=$((9002 + port_offset))

    # Dev mode overrides
    if [ "$DEV_MODE" = true ]; then
        ZOKAI_INSTANCE="${ZOKAI_INSTANCE}-dev"
        VSCODE_PORT=$((VSCODE_PORT + 10000))
        DATA_DIR="${DATA_DIR}-dev"
        # Shift subnets by +20 for dev
        SUBNET_FRONTEND="${SUBNET_FRONTEND/172.3/172.5}"  # free-dev: 172.51
        SUBNET_FRONTEND="${SUBNET_FRONTEND/172.4/172.6}"  # pro-dev:  172.61
        SUBNET_FRONTEND="${SUBNET_FRONTEND/172.2/172.7}"  # mkn-dev:  172.71
    fi

    # --- Per-tier env file (WO-ENV-1) ---
    if [ "$DEV_MODE" = true ]; then
        ENV_FILE="$DATA_DIR/.env"  # dev: real file lives in DATA_DIR
    else
        ENV_FILE=".env.${TIER}"
    fi

    WORKSPACE_DIR="${WORKSPACE_DIR:-$DATA_DIR/workspaces}"

    # Write to .env — instance, subnets, ports
    update_env_var "ZOKAI_INSTANCE" "$ZOKAI_INSTANCE"
    update_env_var "COMPOSE_PROJECT_NAME" "$ZOKAI_INSTANCE"
    update_env_var "VSCODE_PORT" "$VSCODE_PORT"
    update_env_var "SUBNET_FRONTEND" "$SUBNET_FRONTEND"
    update_env_var "GW_FRONTEND" "$GW_FRONTEND"
    update_env_var "SUBNET_BACKEND" "$SUBNET_BACKEND"
    update_env_var "GW_BACKEND" "$GW_BACKEND"
    update_env_var "SUBNET_DATA" "$SUBNET_DATA"
    update_env_var "GW_DATA" "$GW_DATA"
    update_env_var "SUBNET_MGMT" "$SUBNET_MGMT"
    update_env_var "GW_MGMT" "$GW_MGMT"
    update_env_var "NGINX_HTTP_PORT" "$NGINX_HTTP_PORT"
    update_env_var "NGINX_HTTPS_PORT" "$NGINX_HTTPS_PORT"
    update_env_var "GMAIL_MCP_PORT" "$GMAIL_MCP_PORT"
    update_env_var "GMAIL_DASHBOARD_PORT" "$GMAIL_DASHBOARD_PORT"
    update_env_var "CALENDAR_MCP_PORT" "$CALENDAR_MCP_PORT"
    update_env_var "CALENDAR_DASHBOARD_PORT" "$CALENDAR_DASHBOARD_PORT"
    update_env_var "QDRANT_PORT" "$QDRANT_PORT"
    update_env_var "QDRANT_GRPC_PORT" "$QDRANT_GRPC_PORT"
    update_env_var "REDIS_PORT" "$REDIS_PORT"
    update_env_var "POSTGRES_PORT" "$POSTGRES_PORT"
    update_env_var "WORKSPACE_MGR_PORT" "$WORKSPACE_MGR_PORT"
    update_env_var "SECRETS_MGR_PORT" "$SECRETS_MGR_PORT"
    update_env_var "OAUTH_CALLBACK_PORT" "$OAUTH_CALLBACK_PORT"

    print_info "Instance: $ZOKAI_INSTANCE, Port: $VSCODE_PORT, Data: $DATA_DIR"
}

# --- Main Execution ---

main() {
    echo "╔══════════════════════════════════════════╗"
    echo "║  Zokai™ Station Installer v$VERSION"
    echo "╚══════════════════════════════════════════╝"
    > "$LOG_FILE" # Clear log

    parse_args "$@"

    # --- Auto-Detect Existing Installation ---
    # Source existing per-tier env BEFORE resolving tier (tier may come from env)
    # BUT: preserve CLI flags (--tier, --llm-mode) — they override env
    UPDATE_MODE=false
    local cli_tier="$TIER"
    local cli_llm_mode="$LLM_MODE"

    # Try tier-specific env first, then legacy .env
    local detected_env=""
    if [ -n "$cli_tier" ] && [ -f ".env.${cli_tier}" ]; then
        detected_env=".env.${cli_tier}"
    elif [ -f ".env" ] && [ ! -L ".env" ]; then
        # Legacy single .env — will be migrated after tier is resolved (WO-ENV-4)
        detected_env=".env"
    elif [ -f ".env" ] && [ -L ".env" ]; then
        # Symlinked legacy .env — resolve target
        detected_env=".env"
    fi

    if [ -n "$detected_env" ] && [ -f "$detected_env" ]; then
        safe_source_env "$detected_env"
        UPDATE_MODE=true
        print_step "Existing installation detected — UPDATE mode ($detected_env)"
        echo -e "  ${GREEN}Data directory: ${DATA_DIR:-not set} (preserved)${NC}"
        echo ""
    fi

    # Restore CLI flags (they take precedence over env values)
    if [ -n "$cli_tier" ]; then
        TIER="$cli_tier"
        # CLI tier specified — clear derived paths so they get recalculated for this tier
        unset DATA_DIR ZOKAI_INSTANCE VSCODE_PORT COMPOSE_PROJECT_NAME
    fi
    [ -n "$cli_llm_mode" ] && LLM_MODE="$cli_llm_mode"

    # --- Resolve Tier ---
    resolve_tier

    # --- Derive Instance/Port/Data from Tier ---
    derive_tier_config

    # --- Legacy .env migration (WO-ENV-4) ---
    # If legacy .env exists but per-tier file doesn't, migrate it
    if [ -f ".env" ] && [ ! -f "$ENV_FILE" ]; then
        cp ".env" "$ENV_FILE"
        print_info "Migrated legacy .env → $ENV_FILE"
    fi
    # Remove legacy .env (symlink or file) — Docker Compose auto-loads .env
    # from the project dir, which would mix env vars between tiers
    if [ -f ".env" ] || [ -L ".env" ]; then
        rm -f ".env"
        print_info "Removed legacy .env (Docker Compose auto-load prevention)"
    fi

    # --- Create data dir and env if new install ---
    mkdir -p "$DATA_DIR"
    if [ ! -f "$DATA_DIR/.env" ] && [ "$UPDATE_MODE" != true ]; then
        touch "$ENV_FILE"
    fi
    # If DATA_DIR has a .env but code dir doesn't have per-tier file, restore symlink
    if [ -f "$DATA_DIR/.env" ] && [ ! -L "$ENV_FILE" ] && [ "$UPDATE_MODE" != true ]; then
        ln -sf "$DATA_DIR/.env" "$ENV_FILE"
        safe_source_env "$ENV_FILE"
        UPDATE_MODE=true
        print_step "Restored $ENV_FILE symlink — UPDATE mode"
    fi

    check_prerequisites

    # --- Create External Data Directories (skip if update) ---
    if [ "$UPDATE_MODE" != true ]; then
        print_step "Setting up external data directory: $DATA_DIR"
        mkdir -p "$DATA_DIR"/{qdrant/storage,redis/data,postgres/data,vscode-settings,embedding-models,attachments,logs,secrets}
        mkdir -p "$WORKSPACE_DIR"/{notes,outputs/youtube,outputs/markdownify,_ingest,.zokai/templates}
        print_success "Data directory created at $DATA_DIR"
        print_success "Workspace created at $WORKSPACE_DIR"

        # Seed WELCOME.md (first install only)
        cat > "$WORKSPACE_DIR/WELCOME.md" << 'WELCOME_EOF'
# Welcome to Zokai Station 🌿

Your private AI workstation is up and running.

---

## Quick Start

### Set your Tavily API key _(if not done during install)_

Open `zokai-config.json` in your workspace and set:

```json
"TAVILY_API_KEY": "tvly-your-key-here"
```

Get a free key at [tavily.com](https://tavily.com) — 1,000 free searches/month.

### Start using Kilo Code

Click the **Kilo** icon in the left sidebar, or press `Ctrl+Shift+K`.

Try: *"Research the latest trends in X"* or *"Search my workspace for X"*

---

Full guide → [zokai.ai](https://zokai.ai)

Your credentials and URL are saved in `../access.txt`.
WELCOME_EOF

        # Initialize Git in workspace (for Trace change tracking)
        if [ ! -d "$WORKSPACE_DIR/.git" ]; then
            git -C "$WORKSPACE_DIR" init -q -b main 2>/dev/null || true
            git -C "$WORKSPACE_DIR" config user.email "zokai@local"
            git -C "$WORKSPACE_DIR" config user.name "Zokai Station"
            git -C "$WORKSPACE_DIR" add -A 2>/dev/null || true
            git -C "$WORKSPACE_DIR" commit -q -m "init: Zokai workspace" --allow-empty 2>/dev/null || true
            print_success "Git initialized in workspace (for Trace)"
        fi

        # Create .gitignore (if missing)
        if [ ! -f "$WORKSPACE_DIR/.gitignore" ]; then
            cat > "$WORKSPACE_DIR/.gitignore" << 'GITIGNORE'
.DS_Store
Thumbs.db
.vscode/
.kilo/
_ingest/staging/
*.pdf
*.xlsx
*.docx
*.pptx
GITIGNORE
            print_success "Created workspace .gitignore"
        fi
    fi

    # --- Secrets Directory + Credential Setup ---
    setup_secrets_dir
    setup_openrouter_key
    setup_tavily_key
    configure_scenario

    # --- Write Data Paths to .env ---
    update_env_var "DATA_DIR" "$DATA_DIR"
    update_env_var "WORKSPACE_DIR" "$WORKSPACE_DIR"
    update_env_var "QDRANT_DATA_DIR" "$DATA_DIR/qdrant/storage"
    update_env_var "REDIS_DATA_DIR" "$DATA_DIR/redis/data"
    update_env_var "POSTGRES_DATA_DIR" "$DATA_DIR/postgres/data"
    update_env_var "VSCODE_SETTINGS_DIR" "$DATA_DIR/vscode-settings"
    update_env_var "ATTACHMENTS_DIR" "$DATA_DIR/attachments"
    update_env_var "LOGS_DIR" "$DATA_DIR/logs"
    update_env_var "SECRETS_DIR" "$SECRETS_DIR"

    # --- Retriever Selection (Tavily if key exists, else DuckDuckGo) ---
    setup_retriever

    # --- Symlink per-tier env to external DATA_DIR for persistence ---
    # Dev: ENV_FILE is already at DATA_DIR/.env (real file) — just symlink for Docker Compose
    # Prod: copy .env.${TIER} → DATA_DIR/.env then symlink
    if [ "$DEV_MODE" = true ]; then
        # No separate symlink needed — docker compose reads ENV_FILE via COMPOSE_FILE env or direct path
        # But we symlink .env.dev in code dir for visibility
        ln -sf "$ENV_FILE" .env.dev 2>/dev/null || true
        print_success "Dev .env: $ENV_FILE"
    elif [ ! -L "$ENV_FILE" ]; then
        cp "$ENV_FILE" "$DATA_DIR/.env"
        ln -sf "$DATA_DIR/.env" "$ENV_FILE"
        print_success "Linked $ENV_FILE: $DATA_DIR/.env → code dir"
    fi

    # Generate a random VS Code password if one hasn't been set
    if ! grep -q "^VSCODE_PASSWORD=" "$ENV_FILE" 2>/dev/null; then
        VSCODE_PASSWORD=$(openssl rand -hex 16)
        update_env_var "VSCODE_PASSWORD" "$VSCODE_PASSWORD"
        print_success "Generated VS Code password (stored in .env)"
    else
        VSCODE_PASSWORD=$(grep "^VSCODE_PASSWORD=" "$ENV_FILE" | cut -d= -f2)
    fi

    # Generate a random Redis password if one hasn't been set
    if ! grep -q "^REDIS_PASSWORD=" "$ENV_FILE" 2>/dev/null; then
        REDIS_PASSWORD=$(openssl rand -hex 32)
        update_env_var "REDIS_PASSWORD" "$REDIS_PASSWORD"
        print_success "Generated Redis password (stored in .env)"
    fi

    # Postgres password resolution — 3 sources, strict priority order.
    # CRITICAL: Postgres only reads POSTGRES_PASSWORD_FILE on FIRST DB init (empty $PGDATA).
    # After that the password is baked into the database forever. If we generate a new
    # password but the DB still has the old one, authentication fails.
    # Priority: (1) .env  →  (2) secrets file  →  (3) generate new (first install only)
    # Bug fix: retro 2026-03-10 — installer generated new pw on reinstall, DB kept old one.
    POSTGRES_PASSWORD=""
    # Source 1: .env (most authoritative if present)
    if grep -q "^POSTGRES_PASSWORD=" "$ENV_FILE" 2>/dev/null; then
        POSTGRES_PASSWORD=$(grep "^POSTGRES_PASSWORD=" "$ENV_FILE" | cut -d= -f2)
    fi
    # Source 2: secrets file (survives .env loss — e.g. reinstall from clean checkout)
    if [ -z "$POSTGRES_PASSWORD" ] && [ -s "$SECRETS_DIR/postgres-password.txt" ]; then
        POSTGRES_PASSWORD=$(cat "$SECRETS_DIR/postgres-password.txt" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$POSTGRES_PASSWORD" ]; then
            update_env_var "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD"
            print_success "Restored Postgres password from secrets file → .env"
        fi
    fi
    # Source 3: generate new (only safe when DB has no data yet)
    if [ -z "$POSTGRES_PASSWORD" ]; then
        POSTGRES_PASSWORD=$(openssl rand -hex 16)
        update_env_var "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD"
        echo -n "$POSTGRES_PASSWORD" > "$SECRETS_DIR/postgres-password.txt"
        print_success "Generated Postgres password (stored in .env + secrets)"
    fi
    # Always keep secrets file in sync with .env
    local current_secret=$(cat "$SECRETS_DIR/postgres-password.txt" 2>/dev/null | tr -d '[:space:]')
    if [ "$current_secret" != "$POSTGRES_PASSWORD" ]; then
        echo -n "$POSTGRES_PASSWORD" > "$SECRETS_DIR/postgres-password.txt"
        print_info "Synced Postgres password to secrets file"
    fi

    # Set default embedding model if not already set
    if ! grep -q "^EMBEDDING_MODEL_ID=" "$ENV_FILE" 2>/dev/null; then
        update_env_var "EMBEDDING_MODEL_ID" "sentence-transformers/paraphrase-multilingual-mpnet-base-v2"
        print_success "Set default embedding model (stored in .env)"
    fi

    start_services

    # Stamp installed version
    echo "$VERSION" > "$DATA_DIR/.installed_version"

    print_success "Installation Complete! (v$VERSION, TIER=$TIER)"
    if [ "$UPDATE_MODE" = true ]; then
        echo -e "${GREEN}✓ Upgraded — all data preserved${NC}"
    fi
    echo -e "${GREEN}✓ Tier: $TIER | LLM: $LLM_MODE | Instance: $ZOKAI_INSTANCE${NC}"
    if [ "$DEV_MODE" = true ]; then
        echo -e "${BLUE}Dev overlay active${NC}"
    fi
    echo -e "${GREEN}Access VS Code at: http://localhost:${VSCODE_PORT}${NC}"
    echo -e "${BLUE}Password: ${VSCODE_PASSWORD}${NC}"
    echo -e "${NC}Data directory: $DATA_DIR${NC}"
}


main "$@"
