<#
.SYNOPSIS
Fixed Kilo Code Configuration Script (Windows)

.DESCRIPTION
Configures Kilo Code settings and MCPs within the Docker container.
Intended to be run by the installer or manually.

.NOTES
Author: Zokai Team
#>

$ErrorActionPreference = 'Continue'

# --- Colors ---
function Write-Color($text, $color) {
    Write-Host $text -ForegroundColor $color
}

# --- Helper Functions ---
function Print-Step {
    param ([string]$Message)
    Write-Host "=== $Message ===" -ForegroundColor Green
}

function Print-Info {
    param ([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Print-Error {
    param ([string]$Message)
    Write-Host "Error: $Message" -ForegroundColor Red
}

function Print-Success {
    param ([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Get-VSCode-Container {
    $id = docker ps -q -f name=zokai-free-vs-code
    if (-not $id) {
        $id = docker ps -q -f name=zokai-vs-code
    }
    if (-not $id) {
        $id = docker ps -q -f name=workstation-vs-code
    }
    return $id
}

# --- Main Execution ---

# Ensure script runs from the correct directory (project root)
$scriptPath =Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location "$scriptPath\.."

# Load .env variables (free tier uses .env.free)
$envFile = if (Test-Path ".env.free") { ".env.free" } elseif (Test-Path ".env") { ".env" } else { $null }
if ($envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^([^#=]+)=(.*)") {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }
}

Print-Step "Configuring Kilo Code"

# Get VS Code container with retry
$container_id = ""
$max_retries = 10
$retry_count = 0

while (-not $container_id -and $retry_count -lt $max_retries) {
    $container_id = Get-VSCode-Container
    if (-not $container_id) {
        Print-Info "Waiting for VS Code container to be ready... ($($retry_count + 1)/$max_retries)"
        Start-Sleep -Seconds 3
        $retry_count++
    }
}

if (-not $container_id) {
    Print-Error "VS Code container not found after waiting"
    return
}

Print-Success "Found VS Code container: $container_id"

# Create Kilo Code directories
Print-Step "Creating Kilo Code directories"
docker exec $container_id mkdir -p /home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings 2>$null
docker exec -u root $container_id chmod -R 777 /home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code 2>$null

# Copy settings files
Print-Step "Copying Kilo Code settings"

$config_source = "config/kilo/kilo-settings-import.json"
$enable_external = "true"
if ($env:ENABLE_EXTERNAL_TOOLS) {
    $enable_external = $env:ENABLE_EXTERNAL_TOOLS.ToLower()
}

$PROFILE = $env:PROFILE
if ($PROFILE -eq "ff") {
    Print-Info "F&F Profile detected: Using F&F configuration"
    $config_source = "config/kilo/kilo-settings-cloud-ff.json"
} elseif ($enable_external -eq "false") {
    Print-Info "Privacy Mode detected: Using dedicated privacy configuration"
    $config_source = "config/kilo/kilo-settings-privacy.json"
} else {
    Print-Info "Standard Mode detected: Using standard configuration"
}

if (Test-Path $config_source) {
    docker cp "$config_source" "$container_id`:/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json"
    # Fix permissions after docker cp (docker cp creates files as root, chown fails on Windows bind mounts)
    docker exec -u root $container_id chmod -R 777 /home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings 2>$null
    Print-Success "Kilo Code settings copied from $config_source"
    
    $secretsDir = if ($env:SECRETS_DIR) { $env:SECRETS_DIR } else { "../secrets" }
    if (Test-Path "$secretsDir/openai-api-key.txt") {
        $api_key = Get-Content "$secretsDir/openai-api-key.txt" -Raw -ErrorAction SilentlyContinue
        $api_key = $api_key.Trim()
        if (-not [string]::IsNullOrWhiteSpace($api_key) -and $api_key -ne "PLACEHOLDER") {
            Print-Info "Injecting OpenRouter API key..."
            # Use Python inside container to safely inject API key (handles special characters)
            $config_path = "/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json"
            $python_cmd = "import json; f=open('$config_path','r'); d=json.load(f); f.close(); d['providerProfiles']['apiConfigs']['default']['openRouterApiKey']='$api_key'; f=open('$config_path','w'); json.dump(d,f,indent=4); f.close(); print('API key injected')"
            docker exec -u root $container_id python3 -c "$python_cmd"
            Print-Success "OpenRouter API key injected"
        }
    }
    
    # Overwrite stale Kilo configs in container
    Print-Info "Clearing stale Kilo configs..."
    docker cp "$config_source" "$container_id`:/home/workspace-user/config/kilo/kilo-code-settings-ref.json"
    docker cp "$config_source" "$container_id`:/home/workspace-user/config/kilo/kilo-settings-hybrid.json"
    docker exec -u root $container_id chmod 666 /home/workspace-user/config/kilo/kilo-code-settings-ref.json 2>$null
    docker exec -u root $container_id chmod 666 /home/workspace-user/config/kilo/kilo-settings-hybrid.json 2>$null
    
    if (-not [string]::IsNullOrWhiteSpace($api_key) -and $api_key -ne "PLACEHOLDER") {
         # Use Python to safely inject API key into reference configs
         $ref_path = "/home/workspace-user/config/kilo/kilo-code-settings-ref.json"
         $hybrid_path = "/home/workspace-user/config/kilo/kilo-settings-hybrid.json"
         $python_inject = "import json; f=open('REF_PATH','r'); d=json.load(f); f.close(); d['providerProfiles']['apiConfigs']['default']['openRouterApiKey']='$api_key'; f=open('REF_PATH','w'); json.dump(d,f,indent=4); f.close()"
         docker exec -u root $container_id python3 -c ($python_inject.Replace("REF_PATH", $ref_path))
         docker exec -u root $container_id python3 -c ($python_inject.Replace("REF_PATH", $hybrid_path))
    }
    Print-Success "Stale Kilo configs cleared"

} else {
    Print-Error "Config source $config_source not found"
    if (Test-Path "config/kilo/kilo-settings-import.json") {
         Print-Info "Falling back to standard config"
         docker cp "config/kilo/kilo-settings-import.json" "$container_id`:/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json"
    }
}

# Create MCP settings
Print-Step "Creating MCP settings"

# Generate MCP settings JSON content
$mcp_settings = ""

if ($PROFILE -eq "ff") {
    Print-Info "F&F Profile: Generating Free tier MCP settings..."
    $mcp_settings = @{
        mcpServers = @{
            "gptr-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "gptr-mcp")
                env = @{ GPTR_MODE = "proxy" }
                disabled = $false
                timeout = 900
            }
            "youtube-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "youtube-mcp")
                disabled = $false
                timeout = 900
            }
            "gmail-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "gmail-mcp")
                disabled = $false
                timeout = 900
            }
            "calendar-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "calendar-mcp")
                disabled = $false
                timeout = 900
            }
            "tavily-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "tavily-mcp")
                disabled = $false
                timeout = 300
            }
            "mcp-tasks" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "mcp-tasks")
                disabled = $false
                timeout = 300
            }
            "markdownify-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "markdownify-mcp")
                disabled = $false
                timeout = 300
            }
        }
    }
} else {
    # Standard configuration (simplified for this script, mirroring bash logic)
    $mcp_settings = @{
        mcpServers = @{
            "gptr-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "gptr-mcp")
                env = @{ GPTR_MODE = "proxy" }
                disabled = $false
                timeout = 900
            }
            "gmail-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "gmail-mcp")
                disabled = $false
                timeout = 900
            }
             "calendar-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "calendar-mcp")
                disabled = $false
                timeout = 900
            }
            "youtube-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "youtube-mcp")
                disabled = $false
                timeout = 900
            }
            "mcp-tasks" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "mcp-tasks")
                disabled = $false
                timeout = 300
            }
             "postgres-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "postgres")
                disabled = $false
                timeout = 300
            }
            "markdownify-mcp" = @{
                command = "bash"
                args = @("/home/workspace-user/scripts/mcp-bridge.sh", "markdownify-mcp")
                disabled = $false
                timeout = 300
            }
        }
    }
}

$mcp_json = $mcp_settings | ConvertTo-Json -Depth 5
# Write without BOM using .NET
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText("$PWD/temp_mcp_settings.json", $mcp_json, $utf8NoBom)

# Copy MCP settings to container
docker cp "temp_mcp_settings.json" "$container_id`:/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json"
docker cp "temp_mcp_settings.json" "$container_id`:/home/workspace-user/config/mcp-config.json"

Remove-Item "temp_mcp_settings.json" -ErrorAction SilentlyContinue
Print-Success "MCP settings created and copied"

# Set permissions (chmod instead of chown — chown fails on Windows Docker bind mounts)
docker exec -u root $container_id chmod -R 777 /home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/ 2>$null
docker exec -u root $container_id chmod 666 /home/workspace-user/config/mcp-config.json 2>$null

# Update VS Code settings.json
Print-Step "Updating VS Code settings.json"

# We use the existing Python script inside the container for complex JSON manipulation
# We pass environment variables via -e flag
$python_cmd = "import json; import os; settings_path = '/home/workspace-user/.local/share/code-server/User/settings.json'; config_path = '/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json'; " 
# ... (The rest of the python script is too long to inline reliably in PS command line without messy escaping)
# Better strategy: Run the SAME python command as the bash script, line by line is hard.
# We will trust the bash script's python block. 
# We'll copy the python logic to a temp file inside the container and run it.

$python_script = @"
import json
import os

settings_path = '/home/workspace-user/.local/share/code-server/User/settings.json'
config_path = '/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/config.json'

try:
    print(f'Updating Kilo config at {config_path}...')
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            try:
                kilo_data = json.load(f)
            except json.JSONDecodeError:
                kilo_data = {}
        
        if 'globalSettings' not in kilo_data:
            kilo_data['globalSettings'] = {}
        if 'codebaseIndexConfig' not in kilo_data['globalSettings']:
            kilo_data['globalSettings']['codebaseIndexConfig'] = {}
            
        kilo_data['globalSettings']['codebaseIndexConfig']['codebaseIndexEmbedderBaseUrl'] = 'http://ollama:11434'
        kilo_data['globalSettings']['codebaseIndexConfig']['codebaseIndexQdrantUrl'] = 'http://qdrant:6333'
        
        llm_model = os.environ.get('LLM_MODEL')
        if llm_model:
            print(f'Injecting Model ID: {llm_model}')
            if 'providerProfiles' not in kilo_data:
                kilo_data['providerProfiles'] = {}
            if 'apiConfigs' not in kilo_data['providerProfiles']:
                kilo_data['providerProfiles']['apiConfigs'] = {}
            if 'default' not in kilo_data['providerProfiles']['apiConfigs']:
                kilo_data['providerProfiles']['apiConfigs']['default'] = {}
                
            kilo_data['providerProfiles']['currentApiConfigName'] = 'default'
            kilo_data['providerProfiles']['apiConfigs']['default']['apiModelId'] = llm_model
            kilo_data['providerProfiles']['apiConfigs']['default']['apiProvider'] = 'lmstudio'
            kilo_data['providerProfiles']['apiConfigs']['default']['apiBaseUrl'] = 'http://host.docker.internal:1234/v1'
            
            default_id = kilo_data['providerProfiles']['apiConfigs']['default'].get('id')
            if default_id and 'modeApiConfigs' in kilo_data['providerProfiles']:
                for mode_key in kilo_data['providerProfiles']['modeApiConfigs']:
                    kilo_data['providerProfiles']['modeApiConfigs'][mode_key] = default_id
        
        with open(config_path, 'w') as f:
            json.dump(kilo_data, f, indent=4)
        print('Successfully enforced Docker URLs in Kilo config')

    enable_external = os.environ.get('ENABLE_EXTERNAL_TOOLS', 'true').lower() == 'true'
    mcp_path = '/home/workspace-user/.local/share/code-server/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json'
    
    if not enable_external:
        print(f'Privacy Mode: Disabling external MCP tools in {mcp_path}...')
        if os.path.exists(mcp_path):
            with open(mcp_path, 'r') as f:
                try: mcp_data = json.load(f)
                except: mcp_data = {}
            
            servers = mcp_data.get('mcpServers', {})
            tools_to_disable = ['youtube-mcp', 'gmail-mcp', 'calendar-mcp', 'github-mcp', 'raindrop-mcp', 'gptr-mcp', 'crawl4ai-mcp']
            
            for tool in tools_to_disable:
                if tool in servers:
                    del servers[tool]
            
            with open(mcp_path, 'w') as f:
                json.dump(mcp_data, f, indent=4)

    if os.path.exists(settings_path):
        with open(settings_path, 'r') as f:
            try: data = json.load(f)
            except json.JSONDecodeError: data = {}
    else:
        data = {}

    data['kilo-code.autoImportSettingsPath'] = config_path
    data['browse-lite.chromeExecutable'] = '/usr/bin/chromium'

    with open(settings_path, 'w') as f:
        json.dump(data, f, indent=4)
        
    print('Successfully updated settings.json')
except Exception as e:
    print(f'Error updating configuration: {e}')
    # Do not exit 1 — let the installer continue regardless
"@

# Write without BOM using .NET
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText("$PWD/temp_config_script.py", $python_script, $utf8NoBom)
docker cp "temp_config_script.py" "$container_id`:/tmp/config_script.py"
Remove-Item "temp_config_script.py" -ErrorAction SilentlyContinue

# Execute python script in container
$LLM_MODEL = $env:LLM_MODEL
$ENABLE_EXTERNAL_TOOLS_VAL = if ($env:ENABLE_EXTERNAL_TOOLS) { $env:ENABLE_EXTERNAL_TOOLS } else { "true" }
docker exec -u root -e ENABLE_EXTERNAL_TOOLS="$ENABLE_EXTERNAL_TOOLS_VAL" -e LLM_MODEL="$LLM_MODEL" $container_id python3 /tmp/config_script.py

if ($LASTEXITCODE -eq 0) {
    Print-Success "VS Code settings updated"
} else {
    Print-Error "Failed to update VS Code settings"
}

# Documents link
Print-Step "Configuring Documents link"
docker exec $container_id mkdir -p /home/workspace-user/Documents 2>$null
docker exec $container_id ln -sf /home/workspace-user/youtube_output /home/workspace-user/Documents/youtube_output 2>$null
Print-Success "Documents configuration complete"

Print-Success "Kilo Code configuration completed"
Print-Info "Please restart VS Code to apply the settings"
