#!/bin/bash

echo "Starting VS Code Server..."
# Run workspace initialization to ensure README and symlinks exist (runtime bind mount overwrites build-time init)
source /home/workspace-user/init-workspace.sh

# Clear cached layout state when script version changes or on fresh install
# VS Code caches view locations in workspaceStorage (layout only)
# NOTE: Do NOT clear globalStorage as it contains Kilo's workspace state
ZOKAI_SCRIPT_VERSION="2026-03-02-v13"
FRESH_INSTALL_MARKER="/home/workspace-user/.local/share/code-server/.zokai-initialized"
CURRENT_VERSION=$(cat "$FRESH_INSTALL_MARKER" 2>/dev/null || echo "none")
if [ "$CURRENT_VERSION" != "$ZOKAI_SCRIPT_VERSION" ]; then
    echo "Fresh install or script update detected (version: $ZOKAI_SCRIPT_VERSION) - clearing cached layout state..."
    rm -rf /home/workspace-user/.local/share/code-server/User/workspaceStorage
    mkdir -p /home/workspace-user/.local/share/code-server/User/workspaceStorage
    echo "$ZOKAI_SCRIPT_VERSION" > "$FRESH_INSTALL_MARKER"
fi

# ─── Embedding Server Readiness Check ───────────────────────────────────────
# The embedding-server downloads models lazily from HuggingFace on first start
# (~1GB for paraphrase-multilingual-mpnet-base-v2). If Kilo initializes before the model
# is ready, codebase indexing fails with "not properly configured" and caches
# the error state. This check forces a warm-up request and waits for completion.
#
# NOTE: set -e is inherited from init-workspace.sh (sourced above). We disable
# it here so curl failures don't crash the startup script.
set +e
echo "Waiting for embedding-server to be ready..."
EMBED_TIMEOUT=120
EMBED_ELAPSED=0
EMBED_READY=false
while [ "$EMBED_ELAPSED" -lt "$EMBED_TIMEOUT" ]; do
    # Send a real embedding request to force model download + warm-up
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        http://embedding-server:7997/v1/embeddings \
        -H "Content-Type: application/json" \
        -d '{"input":"warmup","model":"sentence-transformers/paraphrase-multilingual-mpnet-base-v2"}' \
        --connect-timeout 5 --max-time 30 2>/dev/null || true)
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    if [ "$HTTP_CODE" = "200" ]; then
        EMBED_READY=true
        break
    fi
    echo "  embedding-server not ready yet (${EMBED_ELAPSED}s / ${EMBED_TIMEOUT}s)..."
    sleep 5
    EMBED_ELAPSED=$((EMBED_ELAPSED + 5))
done
if [ "$EMBED_READY" = true ]; then
    echo "  ✅ Embedding-server ready (model loaded in ${EMBED_ELAPSED}s)"
else
    echo "  ⚠️  Embedding-server not ready after ${EMBED_TIMEOUT}s — codebase indexing may fail"
fi
set -e

# CRITICAL: Sync Kilo Code configuration FIRST, before ANY extensions load
# This prevents the race condition where Kilo loads with stale/default config
echo "Pre-syncing Kilo Code configuration..."
mkdir -p /home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings
if [ -f "/home/workspace-user/config/kilo-settings.json" ]; then
    # WO-KILO-MERGE-1: Smart merge — template wins for structure, user wins for credentials.
    # Preserves user-entered API keys (apiKey, anthropicApiKey, openAiApiKey, etc.) across restarts.
    # On first run (no live config), behaviour is identical to the old blind `cp`.
    python3 -c "
import json, copy, os

USER_KEYS = {
    'apiKey', 'openRouterApiKey', 'zaiApiKey', 'anthropicApiKey',
    'openAiApiKey', 'geminiApiKey', 'awsAccessKey', 'awsSecretKey',
    'baseUrl', 'openAiBaseUrl',
}

template_path = '/home/workspace-user/config/kilo-settings.json'
config_path   = '/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json'

with open(template_path) as f:
    template = json.load(f)

# Load live config (first run: empty dict, same result as old blind cp)
live = {}
if os.path.exists(config_path):
    try:
        with open(config_path) as f:
            live = json.load(f)
    except json.JSONDecodeError:
        print('  WARNING: live config.json corrupt — using template as base')

# Stash (1) user credential keys within known profiles
# Stash (2) entirely user-created profiles (names not in template)
live_api_configs = live.get('providerProfiles', {}).get('apiConfigs', {})
template_api_configs = template.get('providerProfiles', {}).get('apiConfigs', {})
user_keys_stash = {}       # key → {credKey: value} for template profiles
user_profiles_stash = {}   # profile → full cfg for user-created profiles
for profile, cfg in live_api_configs.items():
    if profile not in template_api_configs:
        # Entirely user-created — preserve the whole profile
        user_profiles_stash[profile] = cfg
    else:
        # Template profile — stash only user credential keys
        saved = {k: v for k, v in cfg.items() if k in USER_KEYS and v}
        if saved:
            user_keys_stash[profile] = saved

# Merge: template wins at top level (structural config, model routing, new Zokai profiles)
result = copy.deepcopy(live)
result.update(template)

merged_api_configs = (result.setdefault('providerProfiles', {})
                            .setdefault('apiConfigs', {}))

# Restore (1) user credential keys in template profiles (only where template left blank)
for profile, saved_keys in user_keys_stash.items():
    if profile in merged_api_configs:
        for k, v in saved_keys.items():
            if not merged_api_configs[profile].get(k):
                merged_api_configs[profile][k] = v
        print(f'  Preserved user keys for [{profile}]: {list(saved_keys.keys())}')

# Restore (2) user-created profiles in full
for profile, cfg in user_profiles_stash.items():
    merged_api_configs[profile] = cfg
    print(f'  Preserved user-created profile: [{profile}]')

with open(config_path, 'w') as f:
    json.dump(result, f, indent=2)
print('  Kilo config smart-merged (structure enforced, user credentials + profiles preserved)')
"
    echo "  Kilo config pre-synced successfully"

    # Inject OpenRouter API key from Docker secret (replaces PLACEHOLDER)
    if [ -f "/run/secrets/openrouter-api-key" ]; then
        python3 -c "
import json
secret = open('/run/secrets/openrouter-api-key').read().strip()
config_path = '/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json'
with open(config_path) as f:
    config = json.load(f)
configs = config.get('providerProfiles', {}).get('apiConfigs', {})
# Inject into 'default' profile
if 'default' in configs:
    configs['default']['openRouterApiKey'] = secret
# Inject into 'OR_GLM_5' profile (also uses OpenRouter)
if 'OR_GLM_5' in configs:
    configs['OR_GLM_5']['openRouterApiKey'] = secret
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
print('  OpenRouter API key injected into default + OR_GLM_5 profiles')
"
    else
        echo "  WARNING: /run/secrets/openrouter-api-key not found — API key not injected"
    fi

    # Inject Z.AI API key from Docker secret (for GLM_4.7 direct profile)
    if [ -f "/run/secrets/zai-api-key" ]; then
        python3 -c "
import json
secret = open('/run/secrets/zai-api-key').read().strip()
config_path = '/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json'
with open(config_path) as f:
    config = json.load(f)
configs = config.get('providerProfiles', {}).get('apiConfigs', {})
if 'GLM_4.7' in configs:
    configs['GLM_4.7']['zaiApiKey'] = secret
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
print('  Z.AI API key injected into GLM_4.7 profile')
"
    else
        echo "  WARNING: /run/secrets/zai-api-key not found — Z.AI key not injected"
    fi

    # Enforce codebase indexing config (Kilo onboarding can overwrite config.json, stripping this)
    # NOTE: Kilo Code uses top-level 'codebaseIndexConfig' with 'openAiCompatible*' property names
    python3 -c "
import json, os
config_path = '/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json'
with open(config_path) as f:
    config = json.load(f)
ci = config.get('codebaseIndexConfig', {})
if not ci.get('openAiCompatibleApiKey'):
    config['codebaseIndexConfig'] = {
        'enabled': True,
        'embedderProvider': 'openai-compatible',
        'openAiCompatibleBaseUrl': 'http://embedding-server:7997/v1',
        'openAiCompatibleApiKey': 'not-needed',
        'openAiCompatibleModelId': os.getenv('EMBEDDING_MODEL_ID', 'sentence-transformers/paraphrase-multilingual-mpnet-base-v2'),
        'openAiModelDimension': 768,
        'vectorStoreProvider': 'qdrant',
        'qdrantUrl': 'http://qdrant:6333',
        'searchMinScore': 0.4,
        'searchMaxResults': 20
    }
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    print('  Codebase indexing config enforced (current schema)')
else:
    print('  Codebase indexing config already present')

# TEMP HOTFIX: Disable codebase indexing to break infinite re-index loop
# Kilo 5.9.0 bug: index cache never saves, causing endless re-embedding
# Remove this block once Kilo is upgraded or bug is patched
config['codebaseIndexConfig']['enabled'] = False
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
print('  ⚠️  Codebase indexing DISABLED (hotfix for re-index loop)')
"
fi
if [ -f "/home/workspace-user/config/mcp-config.cloud.json" ]; then
    cp /home/workspace-user/config/mcp-config.cloud.json /home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json 2>/dev/null || true
    echo "  MCP config pre-synced (cloud mode - SSE transport)"
elif [ -f "/home/workspace-user/config/mcp-config.json" ]; then
    cp /home/workspace-user/config/mcp-config.json /home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json 2>/dev/null || true
    echo "  MCP config pre-synced (local mode - stdio transport)"
fi

# Sync custom modes from config.json → custom_modes.yaml
# Kilo v5.10+ reads custom modes from custom_modes.yaml (NOT kilo_custom_modes.json)
# If we only copy config.json, the UI keeps displaying stale roleDefinition/customInstructions
python3 -c "
import json, os

try:
    import yaml
except ImportError:
    import subprocess
    subprocess.check_call(['pip', 'install', 'pyyaml', '-q'])
    import yaml

settings_dir = '/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings'
config_path = os.path.join(settings_dir, 'config.json')
yaml_path = os.path.join(settings_dir, 'custom_modes.yaml')
# Also write legacy JSON for backwards compatibility
json_path = os.path.join(settings_dir, 'kilo_custom_modes.json')

if not os.path.exists(config_path):
    print('  No config.json found, skipping custom modes sync')
    exit(0)

with open(config_path) as f:
    config = json.load(f)

source_modes = config.get('globalSettings', {}).get('customModes', [])
if not source_modes:
    print('  No custom modes in config.json, skipping')
    exit(0)

# Load existing custom_modes.yaml (or start fresh)
try:
    with open(yaml_path) as f:
        yaml_data = yaml.safe_load(f) or {}
except:
    yaml_data = {}

live_modes = yaml_data.get('customModes', [])

# Build lookup of existing modes by slug
live_by_slug = {m.get('slug'): i for i, m in enumerate(live_modes)}

updated = 0
for src_mode in source_modes:
    slug = src_mode.get('slug')
    if not slug:
        continue
    if slug in live_by_slug:
        idx = live_by_slug[slug]
        live_modes[idx] = src_mode
        updated += 1
    else:
        live_modes.append(src_mode)
        updated += 1

yaml_data['customModes'] = live_modes

with open(yaml_path, 'w') as f:
    yaml.dump(yaml_data, f, default_flow_style=False, allow_unicode=True, width=1000)

# Also write legacy JSON for any tools that still read it
with open(json_path, 'w') as f:
    json.dump(live_modes, f, indent=4, ensure_ascii=False)

print(f'  Custom modes synced: {updated} updated, {len(live_modes)} total (YAML + JSON)')
"

# CRITICAL: Create settings.json with Kilo-specific settings BEFORE extensions are installed
# This ensures Kilo reads the auto-import path and sidebar location on first initialization
mkdir -p /home/workspace-user/.local/share/code-server/User
if [ ! -f "/home/workspace-user/.local/share/code-server/User/settings.json" ]; then
    cat > /home/workspace-user/.local/share/code-server/User/settings.json << 'EARLY_SETTINGS'
{
    "kilo-code.autoImportSettingsPath": "/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json",
    "workbench.view.kilo-code-ActivityBar.location": "auxiliary",
    "kilocode.kilo.sidebarLocation": "secondary-side-bar",
    "workbench.auxiliaryBar.visible": true
}
EARLY_SETTINGS
    echo "Early settings.json created with Kilo config"
fi

# Create extensions directory if it doesn't exist
mkdir -p /home/workspace-user/.local/share/code-server/extensions

# Function to install extension if not already installed
install_extension() {
    local extension_id="$1"
    local extension_name="$2"
    
    # Check both the full extension ID and the published name (sometimes they differ in dir name)
    # Generic check: is there a directory matching *extension_id*?
    if ! ls /home/workspace-user/.local/share/code-server/extensions/${extension_id}* 1> /dev/null 2>&1; then
        echo "Installing $extension_name..."
        code-server --install-extension "$extension_id" --user-data-dir /home/workspace-user/.local/share/code-server || echo "Failed Installing Extensions: $extension_id"
    else
        echo "$extension_name already installed"
    fi
}

# Install core extensions
install_extension "foam.foam-vscode" "Zokai Notes (PKM)"
install_extension "ms-python.python" "Python"
install_extension "ms-python.vscode-pylance" "Python Language Server"
install_extension "ms-vscode.vscode-json" "JSON"
install_extension "redhat.vscode-yaml" "YAML"
install_extension "ms-vscode.vscode-typescript-next" "TypeScript"
install_extension "bradlc.vscode-tailwindcss" "Tailwind CSS"
install_extension "esbenp.prettier-vscode" "Prettier"
install_extension "ms-vscode.vscode-eslint" "ESLint"
# Sideload Zokai Trace Editor (markdown WYSIWYG with Zokai features)
# Always force-install to pick up VSIX updates across container rebuilds
if [ -f "/home/workspace-user/config/zokai-trace-editor.vsix" ]; then
    echo "Installing Zokai Trace Editor from VSIX..."
    code-server --install-extension "/home/workspace-user/config/zokai-trace-editor.vsix" --force --user-data-dir /home/workspace-user/.local/share/code-server || echo "Failed Installing: zokai-trace-editor"
else
    echo "WARNING: zokai-trace-editor.vsix not found in config"
fi
# Office Viewer for xlsx/csv (coexists with Trace Editor — no conflict since viewTypes are different)
install_extension "cweijan.vscode-office" "Office Viewer"
install_extension "antfu.browse-lite" "Browse Lite (Embedded Browser)"

# Install Kilo Code from pinned VSIX (WO-KILO-1: marketplace fallback removed)
# Version is pinned by installer.sh — upgrade via branch workflow (see kilo_vsix_version_control_spec.md §3.4)
# FIX (2026-03-26): Conditional install — skip if installed version matches VSIX version.
# Force-reinstall resets extension state (including codebase index cache), triggering a
# 5-10 min re-indexing storm that saturates embedding-server and VS Code CPU.
# FIX (2026-03-25): Clear stale removal markers that block reinstall with
# "Please restart VS Code before reinstalling" — prevents infinite restart loop.
if [ -f "/home/workspace-user/config/kilo_code.vsix" ]; then
    # Clean stale .obsolete markers and .disabled dirs before install attempt
    for kilo_dir in /home/workspace-user/.local/share/code-server/extensions/kilocode.kilo-code-*; do
        if [ -f "$kilo_dir/.obsolete" ]; then
            echo "  Clearing stale .obsolete marker: $kilo_dir"
            rm -f "$kilo_dir/.obsolete"
        fi
        case "$kilo_dir" in
            *.disabled)
                new_name="${kilo_dir%.disabled}"
                echo "  Re-enabling disabled extension: $kilo_dir -> $new_name"
                mv "$kilo_dir" "$new_name"
                ;;
        esac
    done

    # Compare installed version vs VSIX version — only force-install on mismatch
    INSTALLED_VERSION=$(ls -1d /home/workspace-user/.local/share/code-server/extensions/kilocode.kilo-code-* 2>/dev/null | grep -v '.disabled' | head -1 | sed 's/.*kilocode.kilo-code-//')
    VSIX_VERSION=$(unzip -p /home/workspace-user/config/kilo_code.vsix extension/package.json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])" 2>/dev/null || echo "unknown")

    if [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" = "$VSIX_VERSION" ]; then
        echo "Kilo Code $INSTALLED_VERSION already installed — skipping reinstall (preserves index cache)"
    else
        echo "Installing Kilo Code from pinned VSIX (installed=$INSTALLED_VERSION, vsix=$VSIX_VERSION)..."
        code-server --install-extension "/home/workspace-user/config/kilo_code.vsix" --force --user-data-dir /home/workspace-user/.local/share/code-server || {
            echo "  WARNING: Kilo VSIX install failed — checking if already installed..."
            if ls /home/workspace-user/.local/share/code-server/extensions/kilocode.kilo-code-* 1>/dev/null 2>&1; then
                echo "  Kilo extension directory exists — continuing with existing install"
            else
                echo "  ERROR: Kilo not installed and VSIX install failed!"
            fi
        }
    fi
else
    echo "ERROR: kilo_code.vsix not found in config! Run installer.sh to download the pinned VSIX."
fi

# === Kilo Task History Archival (WO-STAB-2) ===
# Compress old task histories to cold storage to prevent memory bloat (909MB incident 2026-03-25).
# Audit data is preserved (tar.gz), not deleted — contains MCP calls, human corrections, diffs.
TASK_DIR="/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/tasks"
ARCHIVE_DIR="/home/workspace-user/kilo-task-archive"
KEEP_HOT=50

if [ -d "$TASK_DIR" ]; then
    mkdir -p "$ARCHIVE_DIR"
    TOTAL=$(ls -1 "$TASK_DIR" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$TOTAL" -gt "$KEEP_HOT" ]; then
        COLD=$((TOTAL - KEEP_HOT))
        echo "Archiving $COLD old Kilo tasks (keeping $KEEP_HOT hot)..."
        ls -1t "$TASK_DIR" | tail -n "$COLD" | while read d; do
            tar czf "$ARCHIVE_DIR/${d}.tar.gz" -C "$TASK_DIR" "$d" 2>/dev/null && rm -rf "$TASK_DIR/$d"
        done
        echo "  Archived $COLD tasks to $ARCHIVE_DIR"
    else
        echo "Kilo task history: $TOTAL tasks (within $KEEP_HOT limit, no archival needed)"
    fi
fi

# === Extension Cleanup ===
# Remove stale Dendron extensions (legacy cleanup)
for dendron_ext in dendron.dendron dendron.dendron-paste-image; do
    if ls /home/workspace-user/.local/share/code-server/extensions/${dendron_ext}* 1> /dev/null 2>&1; then
        echo "Removing stale $dendron_ext extension..."
        code-server --uninstall-extension "$dendron_ext" --user-data-dir /home/workspace-user/.local/share/code-server 2>/dev/null || rm -rf /home/workspace-user/.local/share/code-server/extensions/${dendron_ext}*
    fi
done

# Zokai Notes uses standard VS Code views (backlinks, graph) — no panel pruning needed

# === SME UI Profile: Browse Lite Activity Bar Icon ===
# Adds a globe icon to the Activity Bar for Browse Lite with a welcome panel
echo "Applying SME UI profile: Browse Lite Activity Bar icon..."
python3 -c "
import json, glob, os

pkgs = glob.glob('/home/workspace-user/.local/share/code-server/extensions/antfu.browse-lite-*/package.json')
for p in pkgs:
    ext_dir = os.path.dirname(p)
    with open(p, 'r') as f:
        d = json.load(f)
    contrib = d.setdefault('contributes', {})
    # Add Activity Bar viewContainer
    contrib['viewsContainers'] = {
        'activitybar': [{
            'id': 'browse-lite-container',
            'title': 'Zokai Station',
            'icon': 'resources/compass-icon.svg'
        }]
    }
    contrib['views'] = {
        'browse-lite-container': [{
            'id': 'browse-lite.welcome',
            'name': 'Zokai Station'
        }]
    }
    contrib['viewsWelcome'] = [{
        'view': 'browse-lite.welcome',
        'contents': 'Open a website in the built-in browser.\\n[Browser](command:zokai.openBrowser)\\n\\nView your knowledge graph.\\n[Knowledge Graph](command:zokai.openKnowledgeGraph)\\n\\nOpen the Zokai Station dashboard.\\n[Dashboard](command:zokai.openDashboard)'
    }]
    with open(p, 'w') as f:
        json.dump(d, f, indent=2)
    # Create compass SVG icon (replaces globe — better fit for Browser+Graph+Dashboard hub)
    svg_path = os.path.join(ext_dir, 'resources', 'compass-icon.svg')
    os.makedirs(os.path.dirname(svg_path), exist_ok=True)
    with open(svg_path, 'w') as f:
        f.write('<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><circle cx=\"12\" cy=\"12\" r=\"10\"/><polygon points=\"16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76\"/></svg>')
    print(f'  Browse Lite: Compass icon added')
"

# === Kilo Code: Rebrand for SME users ===
# Patches Kilo extension for user-friendly branding:
# 1. package.nls.json: displayName, description, sidebar title
# 2. webview JS: welcome text "Generate, refactor, and debug code..."
echo "Rebranding Kilo Code for SME users..."
python3 -c "
import json, glob, os

for ext_dir in glob.glob('/home/workspace-user/.local/share/code-server/extensions/kilocode.kilo-code-*'):
    # 1. Patch NLS strings
    nls = os.path.join(ext_dir, 'package.nls.json')
    if os.path.exists(nls):
        with open(nls) as f:
            d = json.load(f)
        patches = {
            'extension.displayName': ('Coding Agent', 'Kilo — Your AI Assistant'),
            'extension.description': ('coding agent', 'Your AI assistant inside Zokai Station. Ask questions about your emails, calendar, notes, and files — or get help writing, planning, and organizing.'),
            'views.activitybar.title': ('Kilo Code', 'Kilo'),
            'views.sidebar.name': ('Kilo Code', 'Kilo'),
        }
        changed = False
        for key, (marker, new_val) in patches.items():
            val = d.get(key, '')
            if marker.lower() in val.lower() and val != new_val:
                d[key] = new_val
                changed = True
        if changed:
            with open(nls, 'w') as f:
                json.dump(d, f, indent=2)
            print(f'  NLS patched: {d.get(\"extension.displayName\", \"\")}')

    # 2. Patch webview welcome text
    for js in glob.glob(os.path.join(ext_dir, 'webview-ui/build/assets/chunk-*.js')):
        with open(js) as f:
            content = f.read()
        old = 'Generate, refactor, and debug code with AI assistance.'
        new = 'Your AI assistant — emails, calendar, notes, and more.'
        if old in content:
            with open(js, 'w') as f:
                f.write(content.replace(old, new))
            print('  Webview welcome text patched')
"

# === Zokai Notes: Rebrand Foam commands in command palette ===
# Patches foam-vscode extension package.json to replace "Foam:" prefix with "Zokai:"
# Users see "Zokai: Create New Note from Template" instead of "Foam: Create New Note from Template"
echo "Rebranding Foam commands to Zokai Notes..."
python3 -c "
import json, glob

pkgs = glob.glob('/home/workspace-user/.local/share/code-server/extensions/foam.foam-vscode-*/package.json')
for p in pkgs:
    with open(p, 'r') as f:
        d = json.load(f)

    changed = 0
    # Rebrand command titles
    for cmd in d.get('contributes', {}).get('commands', []):
        if 'title' in cmd and cmd['title'].startswith('Foam: '):
            old = cmd['title']
            cmd['title'] = cmd['title'].replace('Foam: ', 'Zokai: ', 1)
            changed += 1

    # Rebrand menu category labels
    for menu_group in d.get('contributes', {}).get('menus', {}).values():
        for item in menu_group:
            if isinstance(item, dict) and item.get('group', '').startswith('Foam'):
                item['group'] = item['group'].replace('Foam', 'Zokai', 1)

    if changed:
        with open(p, 'w') as f:
            json.dump(d, f, indent=2)
        print(f'  Rebranded {changed} Foam commands to Zokai')
    else:
        print(f'  No Foam commands found to rebrand')
"

# === Zokai Notes: Deploy templates for 'Create New Note from Template' command ===
# Templates live in .zokai/templates/ (branded). A symlink from .foam/templates/ lets
# the Foam extension find them where it expects.
echo "Deploying Zokai Notes templates..."
TEMPLATES_DIR="/home/workspace-user/workspaces/.zokai/templates"
mkdir -p "$TEMPLATES_DIR"
# Symlink: .foam/templates -> .zokai/templates (Foam reads from .foam/)
mkdir -p /home/workspace-user/workspaces/.foam
rm -rf /home/workspace-user/workspaces/.foam/templates 2>/dev/null
ln -sf "$TEMPLATES_DIR" /home/workspace-user/workspaces/.foam/templates

# Meeting Notes template
cat > "$TEMPLATES_DIR/meeting-notes.md" << 'TMPL'
---
type: meeting-notes
tags: []
created: $CURRENT_YEAR-$CURRENT_MONTH-$CURRENT_DATE
---

# Meeting: $FOAM_TITLE

**Date**: $CURRENT_YEAR-$CURRENT_MONTH-$CURRENT_DATE
**Attendees**:
**Duration**:

## Agenda

1.

## Decisions

| # | Decision | Owner | Deadline |
|---|----------|-------|----------|
| 1 |  |  |  |

## Action Items

- [ ]
TMPL

# Spike Report template
cat > "$TEMPLATES_DIR/spike-report.md" << 'TMPL'
---
type: spike-report
tags: []
created: $CURRENT_YEAR-$CURRENT_MONTH-$CURRENT_DATE
---

# Spike: $FOAM_TITLE

**Duration**:
**Status**: In Progress

## Hypothesis

## Test Criteria

- **Pass**:
- **Fail**:

## Findings

## Outcome

**Result**: Pass ✅ | Fail ❌ | Partial ⚠️
TMPL

# Daily Log template
cat > "$TEMPLATES_DIR/daily-log.md" << 'TMPL'
---
type: daily-log
tags: []
created: $CURRENT_YEAR-$CURRENT_MONTH-$CURRENT_DATE
---

# Daily Log — $CURRENT_YEAR-$CURRENT_MONTH-$CURRENT_DATE

## Yesterday

-

## Today

- [ ]

## Blockers

-
TMPL

echo "  Templates deployed to .zokai/templates/ (symlinked from .foam/templates/)"

# === Zokai Documentation Seed: Deploy manual + capabilities to .zokai ===
# The Dockerfile COPY's zokai-docs-seed/ into the image, but we need to
# deploy those files to the workspace so they appear in the file explorer.
DOCS_SEED="/home/workspace-user/zokai-docs-seed"
ZOKAI_DIR="/home/workspace-user/workspaces/.zokai"
if [ -d "$DOCS_SEED" ]; then
    echo "Deploying Zokai documentation to .zokai/..."
    mkdir -p "$ZOKAI_DIR"
    for _doc in "$DOCS_SEED"/*.md; do
        _fname=$(basename "$_doc")
        # Only copy if missing or newer — don't overwrite user edits
        if [ ! -f "$ZOKAI_DIR/$_fname" ] || [ "$_doc" -nt "$ZOKAI_DIR/$_fname" ]; then
            cp "$_doc" "$ZOKAI_DIR/$_fname"
            echo "  + $_fname"
        fi
    done
    echo "  Documentation deployed to .zokai/"
else
    echo "  WARNING: zokai-docs-seed not found in image — manual not deployed"
fi

# === Knowledge Weaver v2: Graph Memory Bootstrap (Pro/MKN only) ===
# KW is a Pro tier feature — Free tier uses basic notes without semantic memory
TIER="${TIER:-free}"
if [ "$TIER" != "free" ]; then
    # Ensure the KG memory file directory exists so memory-kg-mcp can read/write immediately
    echo "Bootstrapping Knowledge Weaver graph memory..."
    set +e
    mkdir -p /home/workspace-user/workspaces/notes/kw/memory
    touch /home/workspace-user/workspaces/notes/kw/memory/kg_memory.jsonl 2>/dev/null || true
    # Symlink .aim/memory.jsonl → notes/kw/memory/kg_memory.jsonl
    # The MCP KG auto-detects .git and defaults to .aim/; this ensures all writes
    # land in the intended location regardless of how the server resolves its path
    mkdir -p /home/workspace-user/workspaces/.aim
    if [ ! -L /home/workspace-user/workspaces/.aim/memory.jsonl ]; then
        rm -f /home/workspace-user/workspaces/.aim/memory.jsonl
        ln -s /home/workspace-user/workspaces/notes/kw/memory/kg_memory.jsonl /home/workspace-user/workspaces/.aim/memory.jsonl
    fi
    echo "  KG memory directory ready: notes/kw/memory/"
    set -e

    # === Knowledge Weaver v2: Deploy Kilo rule files (symlinks, not copies) ===
    # Symlink each KW .md file from config → all workspace rule locations Kilo reads.
    # Symlinks ensure edits to core/config/kilo/ are INSTANTLY live in Kilo —
    # no container restart, no manual sync needed.
    # Destinations:
    #   .kilocode/rules/                  ← primary flat rules dir (Kilo auto-discovers all .md here)
    #   .kilocode/rules-knowledge-weaver/ ← KW-specific subdirectory (also scanned)
    #   .kilo/rules-knowledge-weaver/     ← legacy location (some older Kilo versions read this)
    if [ -d "/home/workspace-user/config/kilo/rules-knowledge-weaver" ]; then
        echo "Deploying Knowledge Weaver rules (symlinks)..."
        SRC_KW="/home/workspace-user/config/kilo/rules-knowledge-weaver"
        mkdir -p \
            /home/workspace-user/workspaces/.kilocode/rules \
            /home/workspace-user/workspaces/.kilocode/rules-knowledge-weaver \
            /home/workspace-user/workspaces/.kilo/rules-knowledge-weaver
        for md_file in "$SRC_KW"/*.md; do
            fname=$(basename "$md_file")
            for dest_dir in \
                /home/workspace-user/workspaces/.kilocode/rules \
                /home/workspace-user/workspaces/.kilocode/rules-knowledge-weaver \
                /home/workspace-user/workspaces/.kilo/rules-knowledge-weaver; do
                # Only create symlink if the file exists (or was previously a copy)
                # Always replace — ensures stale copies are upgraded to symlinks
                ln -sf "$md_file" "$dest_dir/$fname"
            done
        done
        echo "  KW rules symlinked → .kilocode/rules/, .kilocode/rules-knowledge-weaver/, .kilo/rules-knowledge-weaver/"
    fi

    # === Knowledge Weaver: Deploy Agent Skills ===
    # Copy KW Agent Skills so Kilo auto-discovers them (loaded on-demand, not always in context)
    if [ -d "/home/workspace-user/config/kilo/skills" ]; then
        echo "Deploying Knowledge Weaver Agent Skills..."
        mkdir -p /home/workspace-user/workspaces/.kilocode/skills
        cp -r /home/workspace-user/config/kilo/skills/* /home/workspace-user/workspaces/.kilocode/skills/ 2>/dev/null || true
        echo "  KW skills deployed to .kilocode/skills/"
    fi

    # === Knowledge Weaver: Deploy Kilo Workflows ===
    # Copy KW Workflows for one-shot automation (e.g., /kw-scan-all.md)
    if [ -d "/home/workspace-user/config/kilo/workflows" ]; then
        echo "Deploying Knowledge Weaver Workflows..."
        mkdir -p /home/workspace-user/workspaces/.kilocode/workflows
        cp -r /home/workspace-user/config/kilo/workflows/* /home/workspace-user/workspaces/.kilocode/workflows/ 2>/dev/null || true
        echo "  KW workflows deployed to .kilocode/workflows/"
    fi
else
    echo "Free tier: Skipping Knowledge Weaver bootstrap (Pro feature)"
fi

# === Dynamic Dashboard URL: always ensure correct nginx hostname ===
ZOKAI_INSTANCE="${ZOKAI_INSTANCE:-zokai}"
echo "Patching dashboard URL for instance: $ZOKAI_INSTANCE"
TRACE_EXT=$(find /home/workspace-user/.local/share/code-server/extensions -maxdepth 1 -name "zokai.zokai-trace-editor-*" -type d | head -1)
if [ -n "$TRACE_EXT" ]; then
    # Handle both pristine (zokai-nginx-proxy) and previously-patched (zokai-*-nginx-proxy) URLs
    sed -i "s|http://zokai[^/]*-nginx-proxy/dashboard|http://${ZOKAI_INSTANCE}-nginx-proxy/dashboard|g" "$TRACE_EXT/out/extension.js"
    echo "  Dashboard URL set to http://${ZOKAI_INSTANCE}-nginx-proxy/dashboard"
fi

# Clear extension cache AND configuration cache so code-server re-reads
# the modified package.json files and doesn't use stale editorAssociations
rm -rf /home/workspace-user/.local/share/code-server/CachedProfilesData 2>/dev/null
rm -rf /home/workspace-user/.local/share/code-server/User/caches/CachedConfigurations 2>/dev/null
echo "  Extension + configuration caches cleared (will be rebuilt on startup)"



# Browse Lite welcome panel: Browser uses native browse-lite.open (set on line 225)
# No overwrite needed — zokai.openBrowser JS injection is fragile and unnecessary

# Config sync is now done at the very start of this script (before extensions load)
# See "Pre-syncing Kilo Code configuration" section at the top

# Create VS Code settings directory and default settings
mkdir -p /home/workspace-user/.local/share/code-server/User

# Create default settings if they don't exist
if [ ! -f "/home/workspace-user/.local/share/code-server/User/settings.json" ]; then
    cat > /home/workspace-user/.local/share/code-server/User/settings.json << 'SETTINGS'
{
    "workbench.colorTheme": "Default Light Modern",
    "workbench.iconTheme": "vs-seti",
    "editor.fontSize": 14,
    "editor.fontFamily": "'Fira Code', 'Droid Sans Mono', 'monospace', monospace",
    "editor.tabSize": 2,
    "editor.insertSpaces": true,
    "editor.wordWrap": "on",
    "editor.minimap.enabled": false,
    "editor.formatOnSave": true,
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "terminal.integrated.shell.linux": "/bin/bash",
    "python.defaultInterpreterPath": "/usr/local/bin/python",
    "python.linting.enabled": true,
    "python.linting.pylintEnabled": true,
    "python.formatting.provider": "black",
    "extensions.autoUpdate": false,
    "extensions.autoCheckUpdates": false,
    "telemetry.enableTelemetry": false,
    "update.mode": "none",
    "security.workspace.trust.untrustedFiles": "open",
    "workbench.startupEditor": "none",
    "explorer.confirmDelete": false,
    "explorer.confirmDragAndDrop": false,
    "workbench.sideBar.location": "left",
    "workbench.auxiliaryBar.visible": true,
    "kilocode.kilo.sidebarLocation": "secondary-side-bar",
    "workbench.view.kilo-code-ActivityBar.location": "auxiliary",
    "workbench.view.foam-vscode.location": "sidebar",
    "workbench.editorAssociations": {
        "*.xlsx": "cweijan.officeViewer",
        "*.csv": "cweijan.officeViewer"
    }
}
SETTINGS
fi

# Create tasks.json to auto-open Welcome + Knowledge Graph
mkdir -p /home/workspace-user/workspaces/.vscode
if [ ! -f "/home/workspace-user/workspaces/.vscode/tasks.json" ]; then
    cat > /home/workspace-user/workspaces/.vscode/tasks.json << 'TASKS'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Open Welcome",
            "type": "shell",
            "command": "sleep 3 && code notes/1.Welcome.md",
            "runOptions": {
                "runOn": "folderOpen"
            },
            "presentation": {
                "reveal": "never",
                "panel": "dedicated"
            }
        },
        {
            "label": "Show Knowledge Graph",
            "type": "shell",
            "command": "sleep 6 && code --execute-command foam-vscode.show-graph",
            "runOptions": {
                "runOn": "folderOpen"
            },
            "presentation": {
                "reveal": "never",
                "panel": "dedicated"
            }
        }
    ]
}
TASKS
fi




# Enforce critical settings (Merge into existing settings.json)
python3 -c "
import json
import os

settings_path = '/home/workspace-user/.local/share/code-server/User/settings.json'
try:
    if os.path.exists(settings_path):
        with open(settings_path, 'r') as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                data = {}
    else:
        data = {}

    # Enforce Office Viewer for Excel/CSV
    if 'workbench.editorAssociations' not in data:
        data['workbench.editorAssociations'] = {}
    data['workbench.editorAssociations']['*.xlsx'] = 'cweijan.officeViewer'
    data['workbench.editorAssociations']['*.csv'] = 'cweijan.officeViewer'

    # Enforce Layout (Kilo on right, Zokai Notes on left)
    data['workbench.view.kilo-code-ActivityBar.location'] = 'auxiliary'
    data['workbench.view.foam-vscode.location'] = 'sidebar'
    data['workbench.sideBar.location'] = 'left'
    data['workbench.auxiliaryBar.visible'] = True
    data['kilocode.kilo.sidebarLocation'] = 'secondary-side-bar'

    # Remove stale Dendron settings
    if 'workbench.view.dendron-view.location' in data:
        del data['workbench.view.dendron-view.location']

    # Enforce Kilo Code Providers (Satisfies persistence tests)
    data['kilo-code.defaultProvider'] = 'gptr-mcp'
    if 'kilo-code.providers' not in data:
        data['kilo-code.providers'] = {
            'gptr-mcp': {
                'type': 'mcp',
                'url': 'http://zokai-gptr-mcp:8000/sse'
            }
        }

    # Auto-run startup tasks (Welcome note + Knowledge Graph)
    data['task.allowAutomaticTasks'] = 'on'

    # Enforce In-Station Browsing: Browse Lite uses real Chromium (no iframe restrictions)
    data['browse-lite.chromeExecutable'] = '/usr/bin/chromium'
    data['browse-lite.startUrl'] = 'https://zokai.ai/'
    data['workbench.externalUriOpeners'] = {
        'http://**': 'browse-lite.open',
        'https://**': 'browse-lite.open'
    }

    # Branding: shorten browser tab title to just "Zokai"
    data['window.title'] = 'Zokai'

    # SME Chrome Cleanup: Hide developer-centric UI elements
    data['workbench.statusBar.visible'] = False
    data['editor.lineNumbers'] = 'off'
    data['editor.minimap.enabled'] = False
    data['editor.glyphMargin'] = False
    data['breadcrumbs.enabled'] = False
    data['workbench.startupEditor'] = 'none'

    # Suppress workspace trust dialog (SME users shouldn't see it; also required for E2E tests)
    data['security.workspace.trust.enabled'] = False
    data['security.workspace.trust.startupPrompt'] = 'never'

    # CRITICAL: Foam file exclusions — prevents Zod validator infinite loop on non-markdown files
    # Root cause: Foam 0.29.x graph scanner enters infinite CPU loop when encountering binary/data files
    # See retrospective: 2026-03-26_kilo_cpu_drain_investigation.md
    data['foam.files.ignore'] = [
        '**/outputs/**',           # YouTube MCP transcript/metadata JSON files
        '**/test/**',              # Demo data (XLSX, CSV, SQL)
        '**/*.xlsx',               # Excel files (binary ZIP format triggers Zod loop)
        '**/*.xls',                # Legacy Excel
        '**/*.csv',                # CSV data files
        '**/*.sql',                # SQL scripts
        '**/*.jsonl',              # JSON Lines (bulk data)
        '**/*.pdf',                # PDF documents
        '**/*.docx',               # Word documents
        '**/*.pptx',               # PowerPoint
        '**/*.zip',                # Archives
        '**/*.tar.gz',             # Compressed archives
        '**/*.png',                # Images
        '**/*.jpg',                # Images
        '**/*.jpeg',               # Images
        '**/*.gif',                # Images
        '**/*.mp4',                # Videos
        '**/*.webm',               # Videos
        '**/.gemini/**',           # Kilo Code internal storage
        '**/node_modules/**',      # Node dependencies
        '**/.git/**',              # Git internals
    ]

    with open(settings_path, 'w') as f:
        json.dump(data, f, indent=4)
        print('Settings updated successfully')

    # Enforce Workspace Settings (Overrides User Settings)
    workspace_path = '/home/workspace-user/workspaces/zokai.code-workspace'
    if os.path.exists(workspace_path):
        with open(workspace_path, 'r') as f:
            try:
                ws_data = json.load(f)
            except:
                ws_data = {'folders': [{'path': '.'}], 'settings': {}}
        
        if 'settings' not in ws_data:
            ws_data['settings'] = {}
            
        # Force Editor Association in Workspace (no *.md — see User settings comment)
        if 'workbench.editorAssociations' not in ws_data['settings']:
             ws_data['settings']['workbench.editorAssociations'] = {}
        if '*.md' not in ws_data['settings']['workbench.editorAssociations']:
            ws_data['settings']['workbench.editorAssociations']['*.md'] = 'default'
        ws_data['settings']['workbench.editorAssociations']['*.xlsx'] = 'cweijan.officeViewer'
        ws_data['settings']['workbench.editorAssociations']['*.csv'] = 'cweijan.officeViewer'

        # Enforce In-Station Browsing in workspace settings
        ws_data['settings']['browse-lite.chromeExecutable'] = '/usr/bin/chromium'
        ws_data['settings']['workbench.externalUriOpeners'] = {
            'http://**': 'browse-lite.open',
            'https://**': 'browse-lite.open'
        }

        with open(workspace_path, 'w') as f:
            json.dump(ws_data, f, indent=4)
            print('Workspace settings updated')

except Exception as e:
    print(f'Error updating settings: {e}')
"

# Create keybindings if they don't exist
if [ ! -f "/home/workspace-user/.local/share/code-server/User/keybindings.json" ]; then
    cat > /home/workspace-user/.local/share/code-server/User/keybindings.json << 'KEYBINDINGS'
[
    {
        "key": "ctrl+s",
        "command": "workbench.action.files.save",
        "when": "editorTextFocus"
    },
    {
        "key": "ctrl+p",
        "command": "workbench.action.quickOpen"
    },
    {
        "key": "ctrl+shift+p",
        "command": "workbench.action.showCommands"
    },
    {
        "key": "ctrl+alt+g",
        "command": "foam-vscode.show-graph"
    },
    {
        "key": "ctrl+alt+l",
        "command": "browse-lite.open"
    }
]
KEYBINDINGS
fi

# Enforce critical keybindings (merge into existing keybindings.json)
# This ensures new keybindings are added even when the file already exists from a previous version
python3 -c "
import json, os

kb_path = '/home/workspace-user/.local/share/code-server/User/keybindings.json'
try:
    if os.path.exists(kb_path):
        with open(kb_path, 'r') as f:
            bindings = json.load(f)
    else:
        bindings = []

    required = [
        {'key': 'ctrl+alt+l', 'command': 'browse-lite.open'},
    ]
    existing_keys = {(b.get('key'), b.get('command')) for b in bindings}
    for r in required:
        if (r['key'], r['command']) not in existing_keys:
            bindings.append(r)
            k, c = r['key'], r['command']
            print(f'  Added keybinding: {k} -> {c}')

    with open(kb_path, 'w') as f:
        json.dump(bindings, f, indent=4)
        print('Keybindings enforced successfully')
except Exception as e:
    print(f'Error enforcing keybindings: {e}')
"

# Kilo auto-update DISABLED (WO-KILO-1: version pinned to VSIX from installer.sh)
# To upgrade: see docs/specs/kilo_vsix_version_control_spec.md §3.4
# Remove any existing Kilo update cron job
(crontab -l 2>/dev/null | grep -v "update_kilo.sh" | crontab -) 2>/dev/null || true

# === Zokai Branding: Favicon Replacement ===
# Replace code-server's default "C≡" favicon with the Zokai blue logo
# Targets: favicon.ico (browser tab), favicon-dark-support.svg (SVG fallback), pwa-icon PNGs
echo "Applying Zokai branding: Replacing code-server favicon..."
sudo python3 -c "
import os, shutil
MEDIA_DIR = '/usr/lib/code-server/src/browser/media'
SRC_PNG   = '/home/workspace-user/Zokai_tree_logo.png'

if not os.path.exists(SRC_PNG):
    print('  WARNING: zokai_logo_accent_blue.png not found — favicon not replaced')
else:
    try:
        from PIL import Image
        img = Image.open(SRC_PNG).convert('RGBA')

        # Generate favicon.ico with multiple standard sizes
        sizes = [(16,16),(32,32),(48,48),(64,64),(128,128)]
        icons = [img.resize(s, Image.LANCZOS) for s in sizes]
        ico_path = os.path.join(MEDIA_DIR, 'favicon.ico')
        icons[0].save(ico_path, format='ICO', sizes=sizes, append_images=icons[1:])
        print(f'  favicon.ico replaced ({ico_path})')

        # Replace PWA PNGs and the SVG fallback
        for size, fname in [(192, 'pwa-icon-192.png'), (512, 'pwa-icon-512.png'),
                             (192, 'pwa-icon-maskable-192.png'), (512, 'pwa-icon-maskable-512.png')]:
            out = img.resize((size, size), Image.LANCZOS)
            out.save(os.path.join(MEDIA_DIR, fname), format='PNG')
        print('  PWA icons replaced')

        # Replace SVG favicon with an <image> wrapper pointing to the PNG data URI
        import base64
        from io import BytesIO
        buf = BytesIO()
        img.resize((64, 64), Image.LANCZOS).save(buf, format='PNG')
        b64 = base64.b64encode(buf.getvalue()).decode()
        svg = f'''<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><image href=\"data:image/png;base64,{b64}\" width=\"64\" height=\"64\"/></svg>'''
        for svg_name in ('favicon.svg', 'favicon-dark-support.svg'):
            with open(os.path.join(MEDIA_DIR, svg_name), 'w') as f:
                f.write(svg)
        print('  SVG favicons replaced')

    except Exception as e:
        print(f'  WARNING: Favicon replacement failed: {e}')
"

# === Zokai Branding: PWA Manifest Override ===
# Patch code-server's manifest.json route handler (vscode.js) to replace hardcoded
# description, display mode, and inject theme/background colors.
# code-server generates the manifest dynamically via a route handler, not a static file.
# The route reads --app-name (already set to 'Zokai Station') for name/short_name,
# but description, display, and colors are hardcoded. We patch the JS source before
# code-server starts (this script runs before `exec code-server` at line ~1266).
echo "Applying Zokai branding: Patching PWA manifest route..."
sudo python3 -c "
import re

VSCODE_JS = '/usr/lib/code-server/out/node/routes/vscode.js'
try:
    with open(VSCODE_JS, 'r') as f:
        code = f.read()

    changed = False

    # 1. Replace description
    old_desc = '\"Run Code on a remote server.\"'
    new_desc = '\"Your Sovereign AI Workstation\"'
    if old_desc in code:
        code = code.replace(old_desc, new_desc)
        changed = True
        print('  manifest: description replaced')

    # 2. Replace display mode: fullscreen → standalone
    #    Target the specific manifest object, not all occurrences
    old_display = 'display: \"fullscreen\"'
    new_display = 'display: \"standalone\"'
    if old_display in code:
        code = code.replace(old_display, new_display, 1)
        changed = True
        print('  manifest: display → standalone')

    # 3. Remove display_override (window-controls-overlay not needed for standalone)
    old_override = '        display_override: [\"window-controls-overlay\"],\n'
    if old_override in code:
        code = code.replace(old_override, '')
        changed = True
        print('  manifest: display_override removed')

    # 4. Inject background_color + theme_color after the display line
    #    These are not present in the original code-server source
    if 'background_color' not in code:
        code = code.replace(
            new_display + ',',
            new_display + ',\n        background_color: \"#0a0c10\",\n        theme_color: \"#5b8fb9\",')
        changed = True
        print('  manifest: background_color + theme_color injected')

    if changed:
        with open(VSCODE_JS, 'w') as f:
            f.write(code)
        print('  PWA manifest route patched successfully')
    else:
        print('  PWA manifest route already patched (no changes needed)')

except Exception as e:
    print(f'  WARNING: PWA manifest patch failed: {e}')
"

# === SME UI Profile: Workbench CSS Injection ===
# Inject CSS into code-server's workbench.html to hide unwanted Activity Bar icons
# This is the only reliable way to control Activity Bar in code-server (state is in browser localStorage)
echo "Applying SME UI profile: Activity Bar CSS injection..."
sudo python3 -c "
import re

path = '/usr/lib/code-server/lib/vscode/out/vs/code/browser/workbench/workbench.html'
try:
    with open(path, 'r') as f:
        html = f.read()
    # Remove any previous injection
    html = re.sub(r'<style>\s*/\* Zokai SME Profile.*?</style>', '', html, flags=re.DOTALL)
    css = '''<style>
  /* Zokai SME Profile: Clean Activity Bar */
  .action-item a[aria-label*=\"Search\"],
  .action-item a[aria-label*=\"Run and Debug\"],
  .action-item a[aria-label*=\"Extensions\"],
  .action-item a[aria-label*=\"Testing\"],
  .action-item a[aria-label*=\"Accounts\"],
  .action-item a[aria-label*=\"Manage\"]
  { display: none !important; }
  /* Hide Timeline panel in Explorer sidebar (redundant with Source Control tab) */
  .pane-header[aria-label=\"Timeline Section\"],
  .pane-body[aria-label=\"Timeline Section\"]
  { display: none !important; }
</style>'''
    html = html.replace('</head>', css + '</head>')
    with open(path, 'w') as f:
        f.write(html)
    print('  Activity Bar CSS injected into workbench.html')
except PermissionError:
    print('  Warning: Cannot write to workbench.html (permission denied). Run as root to apply.')
except Exception as e:
    print(f'  Warning: CSS injection failed: {e}')
"

# === Global Zen Mode: Script Injection into workbench.html ===
# Inject a persistent fullscreen toggle button into the VS Code titlebar
# This works on ALL access ports (8080, 8060, 80) since it modifies code-server itself
echo "Applying Global Zen Mode: Script injection..."
sudo python3 -c "
import re

path = '/usr/lib/code-server/lib/vscode/out/vs/code/browser/workbench/workbench.html'
try:
    with open(path, 'r') as f:
        html = f.read()
    # Remove any previous Zen Mode injection
    html = re.sub(r'<script>\s*/\* Zokai Zen Mode.*?</script>', '', html, flags=re.DOTALL)
    zen_script = '''<script>
  /* Zokai Zen Mode v8 - Injected into workbench.html */
  (function(){
    if(window.self!==window.top)return;
    function inject(){
      if(document.getElementById('zokai-zen-action'))return;
      var c=document.querySelector('.titlebar-right .actions-container');
      if(!c)return false;
      var li=document.createElement('li');
      li.id='zokai-zen-action';
      li.className='action-item menu-entry';
      li.setAttribute('role','presentation');
      li.setAttribute('custom-hover','true');
      var a=document.createElement('a');
      a.className='action-label';
      a.setAttribute('role','button');
      a.setAttribute('aria-label','Zen Mode');
      a.setAttribute('tabindex','0');
      a.title='Zen Mode (Fullscreen)';
      a.style.cssText='display:flex!important;align-items:center;justify-content:center;width:16px;height:16px;padding:3px;cursor:pointer;border-radius:5px;color:inherit';
      a.innerHTML='<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" style=\"display:block\"><path d=\"M15 3h6v6\"/><path d=\"M9 21H3v-6\"/><path d=\"M21 3l-7 7\"/><path d=\"M3 21l7-7\"/></svg>';
      li.appendChild(a);
      c.insertBefore(li,c.firstChild);
      a.addEventListener('click',function(){
        if(!document.fullscreenElement){
          document.documentElement.requestFullscreen().catch(function(){});
        }else{
          document.exitFullscreen().catch(function(){});
        }
      });
      return true;
    }
    setInterval(function(){if(document.body&&!document.getElementById('zokai-zen-action'))inject();},1500);
  })();
</script>'''
    html = html.replace('</head>', zen_script + '</head>')
    with open(path, 'w') as f:
        f.write(html)
    print('  Zen Mode script injected into workbench.html')
except PermissionError:
    print('  Warning: Cannot write to workbench.html (permission denied)')
except Exception as e:
    print(f'  Warning: Zen Mode injection failed: {e}')
"

# === Dashboard Auto-Open: Handled by tasks.json (browse-lite.open on folderOpen) ===

# === Markdown Viewer Toggle: REMOVED ===
# The titlebar toggle was unstable (editorAssociations requires window reload,
# which triggers startup tasks and tab flooding). Instead, users can switch
# per-file via right-click tab → "Reopen Editor With..." or explorer right-click
# → "Open With...". The default is text editor (*.md → "default" in settings).
# Clean up any previously injected toggle script
sudo python3 -c "
import re
path = '/usr/lib/code-server/lib/vscode/out/vs/code/browser/workbench/workbench.html'
try:
    with open(path, 'r') as f:
        html = f.read()
    cleaned = re.sub(r'<script>\s*/\* Zokai WYSIWYG Toggle.*?</script>', '', html, flags=re.DOTALL)
    if cleaned != html:
        with open(path, 'w') as f:
            f.write(cleaned)
        print('  Removed stale WYSIWYG toggle from workbench.html')
    else:
        print('  No WYSIWYG toggle to clean up')
except Exception as e:
    print(f'  Warning: WYSIWYG cleanup failed: {e}')
"

echo "VS Code Server configuration complete"

# Clean up stale Chromium data from previous container instances
# The entire UserData directory persists on the bind-mounted vscode-settings volume.
# Stale crash databases, GPU caches, SingletonLock files, and session state cause
# Browse Lite to fail with "Failed to launch the browser process" errors.
# Wiping the entire directory is safe — Browse Lite recreates it on first launch.
echo "Cleaning stale Chromium data..."
BROWSE_LITE_DIR="/home/workspace-user/.local/share/code-server/User/globalStorage/antfu.browse-lite"
if [ -d "$BROWSE_LITE_DIR/UserData" ]; then
    rm -rf "$BROWSE_LITE_DIR/UserData"
    echo "  Browse Lite UserData wiped (will be recreated on first launch)"
fi
rm -rf /tmp/browse-lite-* 2>/dev/null || true
rm -rf /tmp/chromium-* 2>/dev/null || true
rm -rf /tmp/.org.chromium.Chromium.* 2>/dev/null || true
echo "  Chromium data cleaned"

# Clean up stale code-server IPC socket from previous container crashes
# Hazard (H42): On Google Drive FUSE volumes, Unix sockets from a previous session persist
# after a crash but cannot be stat'd/used (ENOTSUP errno=-95). code-server tries to create
# the socket, fails silently, and extension host processes that attempt to connect crash-loop
# with "uncaughtException: connect ENOTSUP". Force-remove on every startup to prevent this.
echo "Cleaning stale code-server IPC socket..."
rm -f /home/workspace-user/.local/share/code-server/code-server-ipc.sock 2>/dev/null || true
echo "  IPC socket cleaned"

echo "Starting VS Code Server on port 8080..."

# Background: Auto-trigger Kilo codebase indexing after code-server is ready
# Kilo's CodeIndexManager has a race condition where it doesn't auto-initialize
# on window load. Triggering a settings save via command forces initialization.
(
    sleep 15  # Wait for code-server + extensions to fully load
    for i in 1 2 3; do
        if curl -s -o /dev/null http://localhost:8080; then
            code-server --execute-command "workbench.action.openSettings" 2>/dev/null
            sleep 2
            code-server --execute-command "workbench.action.closeActiveEditor" 2>/dev/null
            sleep 1
            code-server --execute-command "kilo-code.startCodebaseIndexing" 2>/dev/null
            echo "  Kilo codebase indexing auto-triggered (attempt $i)"
            break
        fi
        sleep 5
    done
) &

# === URL Relay: External Link Opener for Browse Lite ===
# Clear stale kilo-prompt.json so old dashboard prompts don't re-inject on reload
rm -f /home/workspace-user/workspaces/.gemini/kilo-prompt.json 2>/dev/null

# Runs a tiny HTTP server that receives URLs from the dashboard (via nginx proxy)
# and writes them to a shared file for the host-side watcher to open in the system browser.
# This bypasses Browse Lite's inability to open links in the external browser.
if [ -f "/home/workspace-user/scripts/url-relay.py" ]; then
    echo "Starting URL relay for external link opening..."
    python3 /home/workspace-user/scripts/url-relay.py &
    echo "  URL relay started on port 18099"
fi

# Patch Foam extension: hide developer-focused explorer panels
# (Orphans, Placeholders, Connections — keep Tags, Notes, Related Notes)
# Uses 'when: false' instead of removal to avoid "No view is registered" errors
python3 -c "
import json, glob
hide_views = {
    'foam-vscode.orphans': {'id': 'foam-vscode.orphans', 'name': 'Orphans', 'when': 'false'},
    'foam-vscode.placeholders': {'id': 'foam-vscode.placeholders', 'name': 'Placeholders', 'when': 'false'},
    'foam-vscode.connections': {'id': 'foam-vscode.connections', 'name': 'Connections', 'when': 'false'}
}
for pkg in glob.glob('/home/workspace-user/.local/share/code-server/extensions/foam.foam-vscode-*/package.json'):
    with open(pkg) as f:
        d = json.load(f)
    views = d.get('contributes', {}).get('views', {}).get('explorer', [])
    existing_ids = {v.get('id') for v in views}
    patched = 0
    # Set when:false on existing views
    for v in views:
        if v.get('id') in hide_views and v.get('when') != 'false':
            v['when'] = 'false'
            patched += 1
    # Re-add views that were previously removed (with when:false)
    for vid, vdef in hide_views.items():
        if vid not in existing_ids:
            views.append(vdef)
            patched += 1
    if patched:
        d['contributes']['views']['explorer'] = views
        with open(pkg, 'w') as f:
            json.dump(d, f, indent=2)
        print(f'  Foam: patched {patched} dev panels (when: false)')
    else:
        print('  Foam: panels already hidden')
"

# Start VS Code Server
# Start VS Code Server with default workspace
# Use --ignore-last-opened to prevent browser from trying to restore a broken previous session URL
exec code-server --bind-addr 0.0.0.0:8080 --user-data-dir /home/workspace-user/.local/share/code-server --auth password --app-name 'Zokai Station' --welcome-text 'Your password is in the access.txt file located in your Zokai installation folder (the folder you chose during setup).' --ignore-last-opened /home/workspace-user/workspaces/zokai.code-workspace