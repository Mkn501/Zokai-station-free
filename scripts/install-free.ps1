<#
.SYNOPSIS
Zokai Station Free Tier -- Windows Installer

.DESCRIPTION
Installs Zokai Station (Free Tier) on Windows using Docker Desktop.
Called by install-free.bat which handles the execution policy bypass.
Do not run this script directly -- use install-free.bat instead.

Features:
  - GUI folder dialog for workspace selection
  - Automatic data directory layout (BASE_DIR/workspace/ + BASE_DIR/.zokai/)
  - WELCOME.md and zokai-config.json seeding
  - Full port isolation for parallel tier deployment
  - Update detection with layout migration

.NOTES
Version:   4.0.0-free
Tier:      free (VS Code port 8082, nginx 8081)
Platform:  Windows 10+, Docker Desktop, PowerShell 5+
#>

$ErrorActionPreference = 'Stop'

# --- Constants -------------------------------------------------------------------
$VERSION = (Get-Content "$PSScriptRoot\..\VERSION" -ErrorAction SilentlyContinue) -replace '\s','' | Select-Object -First 1
if (-not $VERSION) { $VERSION = "0.0.0" }

$SCRIPT_ROOT   = Split-Path -Parent $PSScriptRoot          # core/ root
$INSTALL_DIR   = "$env:USERPROFILE\AppData\Local\ZokaiStation-free"
$LOG_FILE      = "$SCRIPT_ROOT\install-free.log"
$ENV_FILE      = "$INSTALL_DIR\.env.free"
$TIER          = "free"
$INSTANCE      = "zokai-free"

# Port allocation -- matches macOS DMG builder for Free tier
$VSCODE_PORT          = 8082
$NGINX_HTTP_PORT      = 8081

# --- Color helpers ---------------------------------------------------------------
function Step   { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function Ok     { param($m) Write-Host "[OK]  $m" -ForegroundColor Green }
function Warn   { param($m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Err    { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }
function Info   { param($m) Write-Host "  --> $m" }
function Log    { param($l,$m) "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] [$l] $m" | Add-Content $LOG_FILE }

function Abort {
    param($message)
    Err $message
    Log "ERROR" $message
    Write-Host ""
    Write-Host "  Installation failed. See log: $LOG_FILE" -ForegroundColor Red
    Write-Host ""
    Read-Host "  Press Enter to exit"
    exit 1
}

# --- Banner ----------------------------------------------------------------------
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host "    Zokai Station Free v$VERSION -- Windows Installer" -ForegroundColor Cyan
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host ""

"" | Set-Content $LOG_FILE
Log "INFO" "Starting Free tier install v$VERSION"

# --- Step 0: Detect update vs fresh install --------------------------------------
Step "Checking for existing installation..."

$IS_UPDATE   = $false
$BASE_DIR    = ""
$WORKSPACE_DIR = ""
$DATA_DIR    = ""
$SECRETS_DIR = ""

if ((Test-Path "$INSTALL_DIR") -and (Test-Path "$INSTALL_DIR\.env.free")) {
    # Recover paths from previous install
    $envContent = Get-Content "$INSTALL_DIR\.env.free" -ErrorAction SilentlyContinue
    $savedBase = ($envContent | Where-Object { $_ -match "^BASE_DIR=" } | Select-Object -First 1) -replace "^BASE_DIR=",""
    $savedWorkspace = ($envContent | Where-Object { $_ -match "^WORKSPACE_DIR=" } | Select-Object -First 1) -replace "^WORKSPACE_DIR=",""
    $savedData = ($envContent | Where-Object { $_ -match "^DATA_DIR=" } | Select-Object -First 1) -replace "^DATA_DIR=",""

    if ($savedBase -and (Test-Path $savedBase)) {
        $IS_UPDATE = $true
        $BASE_DIR = $savedBase
        $WORKSPACE_DIR = "$BASE_DIR\workspace"
        $DATA_DIR = "$BASE_DIR\.zokai"
        $SECRETS_DIR = "$DATA_DIR\secrets"

        $oldVer = (Get-Content "$DATA_DIR\.installed_version" -ErrorAction SilentlyContinue) -replace '\s',''
        if (-not $oldVer) { $oldVer = "unknown" }

        Write-Host ""
        Write-Host "  Existing installation found (v$oldVer)." -ForegroundColor Yellow
        $response = Read-Host "  Update to v$VERSION? Your notes and data will be preserved. [Y/n]"
        if ($response -match '^[Nn]') { exit 0 }
        Ok "Updating from v$oldVer -> v$VERSION"
    }
}

if (-not $IS_UPDATE) {
    Ok "Fresh installation"
}

# --- Step 1: Collect inputs (fresh install only) ---------------------------------
$OPENROUTER_KEY  = ""
$TAVILY_KEY      = ""

if (-not $IS_UPDATE) {
    Step "Configuration"
    Write-Host ""

    # -- Workspace location -- GUI folder browser dialog ----------------------
    Write-Host "  Choose a location for your Zokai workspace." -ForegroundColor White
    Write-Host "  A 'Zokai Station Free' folder will be created there." -ForegroundColor Gray
    Write-Host "  Tip: pick a cloud-synced folder for automatic backup." -ForegroundColor Gray
    Write-Host ""

    Add-Type -AssemblyName System.Windows.Forms
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "Choose a location for Zokai Station Free (e.g. Documents)"
    $folderDialog.RootFolder = [System.Environment+SpecialFolder]::MyComputer
    $folderDialog.SelectedPath = [System.Environment]::GetFolderPath("MyDocuments")
    $folderDialog.ShowNewFolderButton = $true

    $dialogResult = $folderDialog.ShowDialog()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "  Installation cancelled." -ForegroundColor Yellow
        exit 0
    }
    $PARENT_DIR = $folderDialog.SelectedPath.TrimEnd('\')
    $BASE_DIR = "$PARENT_DIR\Zokai Station Free"
    $WORKSPACE_DIR = "$BASE_DIR\workspace"
    $DATA_DIR = "$BASE_DIR\.zokai"
    $SECRETS_DIR = "$DATA_DIR\secrets"
    Ok "Location: $BASE_DIR"
    Write-Host ""

    # -- OpenRouter API key -- secure input ------------------------------------
    Write-Host "  Zokai uses OpenRouter for AI (free plan available)." -ForegroundColor White
    Write-Host "  Get your free key at: https://openrouter.ai/keys" -ForegroundColor Gray
    Write-Host "  (starts with sk-or-...)" -ForegroundColor Gray
    Write-Host ""
    $secureKey = Read-Host "  OpenRouter API key (paste and press Enter, or leave blank)" -AsSecureString
    $OPENROUTER_KEY = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey))
    if (-not $OPENROUTER_KEY) {
        Warn "No API key entered. AI features will use a placeholder until you add a key."
        Warn "Add it later: $SECRETS_DIR\openai-api-key.txt"
        $OPENROUTER_KEY = "PLACEHOLDER"
    } else {
        Ok "OpenRouter key saved"
    }
    Write-Host ""

    # -- Tavily key (optional) ------------------------------------------------
    Write-Host "  Tavily improves web search (optional -- free 1,000 searches/month)." -ForegroundColor White
    Write-Host "  Get key at: https://tavily.com  |  Leave blank to use DuckDuckGo." -ForegroundColor Gray
    Write-Host ""
    $secureTavily = Read-Host "  Tavily API key [press Enter to skip]" -AsSecureString
    $TAVILY_KEY = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureTavily))
    if (-not $TAVILY_KEY) {
        Info "Skipped -- DuckDuckGo will be used for web search"
        $TAVILY_KEY = "PLACEHOLDER"
    } else {
        Ok "Tavily key saved"
    }

    # -- Confirmation ---------------------------------------------------------
    Write-Host ""
    Write-Host "  ----------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Ready to install Zokai Station Free v$VERSION" -ForegroundColor White
    Write-Host "    AI:     OpenRouter (cloud)" -ForegroundColor Gray
    Write-Host "    Folder: $BASE_DIR" -ForegroundColor Gray
    Write-Host "  ----------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    $confirm = Read-Host "  Proceed? [Y/n]"
    if ($confirm -match '^[Nn]') { exit 0 }
}

# --- Step 2: Copy files to INSTALL_DIR -------------------------------------------
Step "Step 1/6: Copying application files..."
# Remove old install entirely to prevent stale files persisting
if (Test-Path $INSTALL_DIR) { Remove-Item $INSTALL_DIR -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null

# Use robocopy to mirror
$excludeDirs = @('.git', '__pycache__', 'data', 'data-dev', '.publish-staging', 'build-free',
                 '.pytest_cache', 'secrets', 'secrets-dev', '.venv', 'exports', 'cloud')
$robocopyArgs = @($SCRIPT_ROOT, $INSTALL_DIR, '/MIR', '/NP', '/NFL', '/NDL', '/NJH', '/NJS')
foreach ($ex in $excludeDirs) { $robocopyArgs += "/XD"; $robocopyArgs += $ex }
$robocopyArgs += "/XF"
$robocopyArgs += "*.log"
$robocopyArgs += "*.dmg"
$robocopyArgs += "nohup.out"
$robocopyArgs += ".env"
$robocopyArgs += ".env.dev"
$robocopyArgs += ".env.backup*"

$result = Start-Process robocopy -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
if ($result.ExitCode -ge 8) {
    Abort "Failed to copy application files (robocopy exit: $($result.ExitCode))"
}
Ok "Application files copied"

# --- Step 1b: Deploy Zokai launcher + shortcuts ----------------------------------
Step "Step 1b/6: Installing launcher..."
$launcherTemplate = "$INSTALL_DIR\ZokaiLauncher"
if (Test-Path $launcherTemplate) {
    # Copy launcher files to INSTALL_DIR root
    Copy-Item "$launcherTemplate\zokai-launcher.ps1" "$INSTALL_DIR\zokai-launcher.ps1" -Force
    Copy-Item "$launcherTemplate\zokai-launcher.bat" "$INSTALL_DIR\zokai-launcher.bat" -Force
    Copy-Item "$launcherTemplate\zokai-station.ico"  "$INSTALL_DIR\zokai-station.ico"  -Force

    # Patch placeholders (UTF-8 no-BOM — Lesson #99)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $psScript  = "$INSTALL_DIR\zokai-launcher.ps1"
    $content   = [System.IO.File]::ReadAllText($psScript)
    $content   = $content -replace '__INSTALL_DIR__', ($INSTALL_DIR -replace '\\', '\\')
    $content   = $content -replace '__DATA_DIR__',    ($DATA_DIR -replace '\\', '\\')
    [System.IO.File]::WriteAllText($psScript, $content, $utf8NoBom)

    # Create Desktop shortcut
    try {
        $wsh     = New-Object -ComObject WScript.Shell
        $lnk     = $wsh.CreateShortcut("$env:USERPROFILE\Desktop\Zokai Station.lnk")
        $lnk.TargetPath       = "$INSTALL_DIR\zokai-launcher.bat"
        $lnk.IconLocation     = "$INSTALL_DIR\zokai-station.ico"
        $lnk.WorkingDirectory = $INSTALL_DIR
        $lnk.WindowStyle      = 7  # Minimized (hides CMD flash)
        $lnk.Save()
        Ok "Desktop shortcut created"
    } catch {
        Warn "Could not create Desktop shortcut: $_"
    }

    # Create Start Menu shortcut
    try {
        $startMenu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Zokai"
        New-Item -ItemType Directory -Force -Path $startMenu -ErrorAction SilentlyContinue | Out-Null
        $lnk2     = $wsh.CreateShortcut("$startMenu\Zokai Station.lnk")
        $lnk2.TargetPath       = "$INSTALL_DIR\zokai-launcher.bat"
        $lnk2.IconLocation     = "$INSTALL_DIR\zokai-station.ico"
        $lnk2.WorkingDirectory = $INSTALL_DIR
        $lnk2.WindowStyle      = 7
        $lnk2.Save()
        Ok "Start Menu shortcut created"
    } catch {
        Warn "Could not create Start Menu shortcut: $_"
    }

} else {
    Warn "ZokaiLauncher template not found -- skipping shortcut creation"
}

# --- Step 3: Create directories --------------------------------------------------
Step "Step 2/6: Creating data directories..."
New-Item -ItemType Directory -Path $BASE_DIR -Force | Out-Null
New-Item -ItemType Directory -Path $DATA_DIR -Force | Out-Null


$dirs = @(
    "$WORKSPACE_DIR\notes",
    "$WORKSPACE_DIR\outputs",
    "$WORKSPACE_DIR\.zokai",
    "$SECRETS_DIR",
    "$DATA_DIR\vscode-settings",
    "$DATA_DIR\qdrant\storage",
    "$DATA_DIR\redis\data",
    "$DATA_DIR\embedding-models",
    "$DATA_DIR\attachments",
    "$DATA_DIR\logs",
    "$DATA_DIR\kilo-task-archive"
)
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# -- Layout migration (v1 -> v2): move user files into workspace/ subdir --
if ($IS_UPDATE -and (Test-Path "$BASE_DIR\notes") -and (-not (Test-Path "$BASE_DIR\workspace"))) {
    Log "INFO" "Migrating to new folder layout (data outside workspace)..."
    New-Item -ItemType Directory -Path $WORKSPACE_DIR -Force | Out-Null
    foreach ($item in @("notes", "outputs", "access.txt", "README.md")) {
        if (Test-Path "$BASE_DIR\$item") {
            Move-Item "$BASE_DIR\$item" "$WORKSPACE_DIR\" -Force -ErrorAction SilentlyContinue
        }
    }
}

# -- Seed zokai-config.json (user-editable model + search config) --
$zokaicfg = "$WORKSPACE_DIR\.zokai\zokai-config.json"
if (-not (Test-Path $zokaicfg)) {
    $src = "$INSTALL_DIR\config\zokai-config.json"
    if (Test-Path $src) { Copy-Item $src $zokaicfg -Force -ErrorAction SilentlyContinue }
}

# -- Seed WELCOME.md into workspace/notes/ --
if (-not (Test-Path "$WORKSPACE_DIR\notes\WELCOME.md")) {
    $welcomeSrc = "$INSTALL_DIR\config\WELCOME.md"
    if (Test-Path $welcomeSrc) { Copy-Item $welcomeSrc "$WORKSPACE_DIR\notes\WELCOME.md" -Force -ErrorAction SilentlyContinue }
}

# -- Inject Tavily key into zokai-config.json --
$effectiveTavily = $TAVILY_KEY
if (-not $effectiveTavily -or $effectiveTavily -eq "PLACEHOLDER") {
    if (Test-Path "$SECRETS_DIR\tavily-api-key.txt") {
        $effectiveTavily = (Get-Content "$SECRETS_DIR\tavily-api-key.txt" -Raw -ErrorAction SilentlyContinue).Trim()
    }
}
if ($effectiveTavily -and $effectiveTavily -ne "PLACEHOLDER" -and (Test-Path $zokaicfg)) {
    try {
        $cfg = Get-Content $zokaicfg | ConvertFrom-Json
        $cfg.TAVILY_API_KEY = $effectiveTavily
        $cfg.RETRIEVER = "tavily"
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($zokaicfg, ($cfg | ConvertTo-Json -Depth 5), $utf8NoBom)
        Log "INFO" "Tavily key injected into zokai-config.json"
    } catch {
        Log "WARN" "Failed to inject Tavily key: $_"
    }
} elseif (Test-Path $zokaicfg) {
    try {
        $cfg = Get-Content $zokaicfg | ConvertFrom-Json
        if ($cfg.RETRIEVER -ne "tavily") {
            $cfg.RETRIEVER = "duckduckgo"
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText($zokaicfg, ($cfg | ConvertTo-Json -Depth 5), $utf8NoBom)
        }
    } catch { }
}

Ok "Directories created"

# Copy launcher to user-visible BASE_DIR (next to access.txt) -- must be after dir creation
# Cannot reuse zokai-launcher.bat directly because %~dp0 would resolve to BASE_DIR
# instead of INSTALL_DIR where zokai-launcher.ps1 lives. Generate a custom BAT.
if (Test-Path "$INSTALL_DIR\zokai-launcher.ps1") {
    $launcherBat = "@echo off`r`npowershell -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$INSTALL_DIR\zokai-launcher.ps1`""
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText("$BASE_DIR\Zokai Station.bat", $launcherBat, $utf8NoBom)
    Copy-Item "$INSTALL_DIR\zokai-station.ico" "$BASE_DIR\zokai-station.ico" -Force -ErrorAction SilentlyContinue
}

# --- Step 4: Write secrets -------------------------------------------------------
Step "Step 3/6: Configuring credentials..."
New-Item -ItemType Directory -Path $SECRETS_DIR -Force | Out-Null

function Write-SecretIfEmpty {
    param($File, $Value, $Fallback = "")
    if (Test-Path $File) {
        $existing = (Get-Content $File -Raw -ErrorAction SilentlyContinue).Trim()
        if ($existing -and $existing -ne "PLACEHOLDER") { return }   # Keep real key
    }
    $out = if ($Value -and $Value -ne "PLACEHOLDER") { $Value } else { $Fallback }
    if ($out) {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($File, $out, $utf8NoBom)
    }
}

Write-SecretIfEmpty "$SECRETS_DIR\openai-api-key.txt"    $OPENROUTER_KEY "PLACEHOLDER"
Write-SecretIfEmpty "$SECRETS_DIR\openrouter-api-key.txt" $OPENROUTER_KEY "PLACEHOLDER"
Write-SecretIfEmpty "$SECRETS_DIR\tavily-api-key.txt"    $TAVILY_KEY     "PLACEHOLDER"

$emptySecrets = @('anthropic-api-key.txt','google-api-key.txt','google-cx.txt',
                   'youtube-api-key.txt','github-token.txt','supabase-key.txt',
                   'raindrop-token.txt','postgres-password.txt','zai-api-key.txt')
foreach ($s in $emptySecrets) {
    if (-not (Test-Path "$SECRETS_DIR\$s")) {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText("$SECRETS_DIR\$s", "PLACEHOLDER", $utf8NoBom)
    }
}
if (-not (Test-Path "$SECRETS_DIR\token.json")) {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText("$SECRETS_DIR\token.json", "{}", $utf8NoBom)
}

# Bundle Google OAuth client credentials (Zokai Station app identity)
if ((-not (Test-Path "$SECRETS_DIR\credentials.json")) -and (Test-Path "$INSTALL_DIR\config\credentials.json")) {
    Copy-Item "$INSTALL_DIR\config\credentials.json" "$SECRETS_DIR\credentials.json" -Force -ErrorAction SilentlyContinue
}

Ok "Credentials configured"

# --- Step 5: Generate .env.free --------------------------------------------------
Step "Step 4/6: Generating configuration..."
Set-Location $INSTALL_DIR
# Remove stale .env files
Remove-Item "$INSTALL_DIR\.env.free" -Force -ErrorAction SilentlyContinue
Remove-Item "$INSTALL_DIR\.env.mkn" -Force -ErrorAction SilentlyContinue
Remove-Item "$INSTALL_DIR\.env.dev" -Force -ErrorAction SilentlyContinue
Remove-Item "$INSTALL_DIR\.env" -Force -ErrorAction SilentlyContinue

# Convert backslash paths to forward slashes for Docker volume mounts
function To-DockerPath { param($p) return $p -replace '\\', '/' }

# Generate passwords
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$pwBytes = New-Object byte[] 16
$rng.GetBytes($pwBytes)
$VSCODE_PASSWORD = ($pwBytes | ForEach-Object { $_.ToString("x2") }) -join ""

$redisBytes = New-Object byte[] 32
$rng.GetBytes($redisBytes)
$REDIS_PASSWORD = ($redisBytes | ForEach-Object { $_.ToString("x2") }) -join ""

$retriever = if ($TAVILY_KEY -and $TAVILY_KEY -ne "PLACEHOLDER") { "tavily" } else { "duckduckgo" }

# URL relay file
$urlQueue = "$DATA_DIR\.open-url-queue"
if (-not (Test-Path $urlQueue)) { "" | Set-Content $urlQueue -NoNewline }

# Build the ENTIRE .env.free as a single array and write ONCE.
# This avoids PowerShell's scalar/array bug that corrupted the file
# when using read-modify-write cycles (Get-Content returns a scalar
# for single-line files, causing += to do string concatenation).
$envLines = @(
    "# Zokai Station Free -- generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "TIER=free"
    "PROFILE=ff"
    "LLM_PROVIDER=openrouter"
    "LLM_MODE=cloud"
    "ENABLE_EXTERNAL_TOOLS=true"
    "ZOKAI_INSTANCE=$INSTANCE"
    "COMPOSE_PROJECT_NAME=$INSTANCE"
    "EMBEDDING_MODEL_ID=sentence-transformers/paraphrase-multilingual-mpnet-base-v2"
    "EMBEDDING_DIMENSIONS=768"
    "VSCODE_PORT=$VSCODE_PORT"
    "NGINX_HTTP_PORT=$NGINX_HTTP_PORT"
    "NGINX_HTTPS_PORT=8443"
    "GMAIL_MCP_PORT=18007"
    "GMAIL_DASHBOARD_PORT=18017"
    "CALENDAR_MCP_PORT=18008"
    "CALENDAR_DASHBOARD_PORT=18018"
    "QDRANT_PORT=26333"
    "QDRANT_GRPC_PORT=26334"
    "REDIS_PORT=16379"
    "POSTGRES_PORT=64322"
    "WORKSPACE_MGR_PORT=19000"
    "SECRETS_MGR_PORT=19001"
    "OAUTH_CALLBACK_PORT=19002"
    "TAVILY_MCP_PORT=18000"
    "SUBNET_FRONTEND=172.31.0.0/16"
    "GW_FRONTEND=172.31.0.1"
    "SUBNET_BACKEND=172.32.0.0/16"
    "GW_BACKEND=172.32.0.1"
    "SUBNET_DATA=172.33.0.0/16"
    "GW_DATA=172.33.0.1"
    "SUBNET_MGMT=172.34.0.0/16"
    "GW_MGMT=172.34.0.1"
    "BASE_DIR=$(To-DockerPath $BASE_DIR)"
    "DATA_DIR=$(To-DockerPath $DATA_DIR)"
    "WORKSPACE_DIR=$(To-DockerPath $WORKSPACE_DIR)"
    "SECRETS_DIR=$(To-DockerPath $SECRETS_DIR)"
    "VSCODE_SETTINGS_DIR=$(To-DockerPath $DATA_DIR\vscode-settings)"
    "QDRANT_DATA_DIR=$(To-DockerPath $DATA_DIR\qdrant\storage)"
    "REDIS_DATA_DIR=$(To-DockerPath $DATA_DIR\redis\data)"
    "EMBEDDING_MODELS_DIR=$(To-DockerPath $DATA_DIR\embedding-models)"
    "ATTACHMENTS_DIR=$(To-DockerPath $DATA_DIR\attachments)"
    "LOGS_DIR=$(To-DockerPath $DATA_DIR\logs)"
    "URL_RELAY_QUEUE=$(To-DockerPath $urlQueue)"
    "RETRIEVER=$retriever"
    "VSCODE_PASSWORD=$VSCODE_PASSWORD"
    "REDIS_PASSWORD=$REDIS_PASSWORD"
)

# Write ONCE, UTF-8 without BOM (Docker Compose is a Linux binary)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($ENV_FILE, ($envLines -join "`n") + "`n", $utf8NoBom)

Log "INFO" "Env file written: $ENV_FILE ($($envLines.Count) vars)"

$VERSION | Set-Content "$DATA_DIR\.installed_version" -NoNewline

# Kilo settings - use the Free tier config
$kiloSrcFf = "$INSTALL_DIR\config\kilo\kilo-settings-cloud-ff.json"
if (Test-Path $kiloSrcFf) {
    Copy-Item $kiloSrcFf "$INSTALL_DIR\config\kilo\kilo-settings-import.json" -Force -ErrorAction SilentlyContinue
    Copy-Item $kiloSrcFf "$INSTALL_DIR\config\kilo-settings.json" -Force -ErrorAction SilentlyContinue
}

Ok "Configuration written to .env.free"

# ===============================================================================
# From here on, NOTHING should abort the script. Every step is best-effort
# so finalization (access.txt, browser) always runs.
# ===============================================================================
$ErrorActionPreference = 'Continue'

try {

# --- Step 6: Build + start containers -------------------------------------------
Step "Step 5/6: Building containers (5-15 min on first install)..."
Info "This downloads the base images -- please be patient."
Write-Host ""

$buildResult = Start-Process docker -ArgumentList "compose","--env-file",$ENV_FILE,"-f","docker-compose.yml","build" `
    -Wait -PassThru -NoNewWindow
if ($buildResult.ExitCode -ne 0) {
    Warn "Some containers failed to build. Core services will still start."
    Warn "You can rebuild failed containers later with:"
    Warn "  docker compose --env-file .env.free build <service-name>"
    Log "WARN" "Container build exited with code $($buildResult.ExitCode)"
} else {
    Ok "All containers built"
}

# Clean stale Docker volumes from previous installs
Log "INFO" "Cleaning stale Docker volumes..."
cmd /c "docker compose --env-file $ENV_FILE -f docker-compose.yml down --volumes 2>nul" | Out-Null

# Ensure workspace directory exists
New-Item -ItemType Directory -Path $WORKSPACE_DIR -Force -ErrorAction SilentlyContinue | Out-Null

Step "Step 5/6: Starting services..."
$coreServices = "vs-code nginx-proxy secrets-manager workspace-manager config-service service-discovery qdrant redis embedding-server"
$baseMcps     = "ingestor gptr-mcp gmail-mcp calendar-mcp youtube-mcp mcp-tasks markdownify-mcp tavily-mcp"
$allServices  = "$coreServices $baseMcps"

$upResult = Start-Process docker -ArgumentList "compose","--env-file",$ENV_FILE,"-f","docker-compose.yml","up","-d","--remove-orphans",$allServices `
    -Wait -PassThru -NoNewWindow
if ($upResult.ExitCode -ne 0) {
    Warn "Some services may not have started. Check Docker Desktop for details."
} else {
    Ok "Services started"
}

# --- Step 7: Configure Kilo Code --------------------------------------------
Step "Step 6/6: Configuring Kilo Code..."
$kiloScript = "$INSTALL_DIR\scripts\configure-kilo-code.ps1"
if (Test-Path $kiloScript) {
    Info "Applying Kilo Code profiles..."
    $kiloProc = Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$kiloScript `
        -WorkingDirectory $INSTALL_DIR -PassThru -NoNewWindow
    # Wait up to 120 seconds — don't let configure-kilo-code.ps1 block forever
    $kiloFinished = $kiloProc.WaitForExit(120000)
    if ($kiloFinished -and $kiloProc.ExitCode -eq 0) {
        Ok "Kilo Code configured"
    } elseif (-not $kiloFinished) {
        Warn "Kilo Code configuration timed out after 120s -- continuing with defaults"
        try { $kiloProc.Kill() } catch { }
    } else {
        Warn "Kilo Code configuration had issues -- will use default settings"
    }
} else {
    Info "Kilo Code configuration skipped (will auto-configure on first launch)"
    Ok "Step 6/6 complete"
}

} catch {
    Warn "An error occurred during setup: $_"
    Log "ERROR" "Post-config error: $_"
} finally {

# ===============================================================================
# FINALIZATION -- this block ALWAYS runs, even if something above crashed.
# ===============================================================================

# Write access.txt
try {
    @"
Zokai Station Free v$VERSION
==============================
URL:      http://localhost:$NGINX_HTTP_PORT
Password: $VSCODE_PASSWORD
Folder:   $BASE_DIR
"@ | Set-Content "$BASE_DIR\access.txt" -Encoding UTF8

    Copy-Item "$BASE_DIR\access.txt" "$WORKSPACE_DIR\access.txt" -Force -ErrorAction SilentlyContinue
    Copy-Item "$BASE_DIR\access.txt" "$INSTALL_DIR\access.txt" -Force -ErrorAction SilentlyContinue
} catch {
    Warn "Could not write access.txt: $_"
}

# Copy uninstall scripts to user-visible folder
if (Test-Path "$INSTALL_DIR\uninstall-free.bat") {
    Copy-Item "$INSTALL_DIR\uninstall-free.bat" "$BASE_DIR\Uninstall Zokai Station.bat" -Force -ErrorAction SilentlyContinue
}

# Start the Windows URL watcher as a DETACHED process.
# Lesson #107: Start-Job is session-scoped -- dies when installer exits.
# Start-Process creates a truly independent process that survives session close.
# This is the Windows equivalent of open-url-watcher.sh on macOS.
# url-relay.py (inside the vs-code container) writes Google OAuth URLs to
# scripts/.open-url-queue -- this watcher picks them up and opens the host browser.
$watcherScript = "$INSTALL_DIR\scripts\open-url-watcher.ps1"
if (Test-Path $watcherScript) {
    Start-Process powershell.exe -ArgumentList "-NoProfile","-WindowStyle","Hidden","-ExecutionPolicy","Bypass","-File",$watcherScript,"-InstallDir",$INSTALL_DIR -WindowStyle Hidden
    Ok "URL watcher started (enables Connect Google button)"
} else {
    Warn "open-url-watcher.ps1 not found -- Connect Google button may not open browser automatically"
}

# Wait for nginx to be reachable, then open browser
Info "Waiting for services to be ready..."
$ready = $false
for ($i = 1; $i -le 12; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$NGINX_HTTP_PORT/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    Start-Sleep -Seconds 5
}

if ($ready) {
    Start-Process "http://localhost:$NGINX_HTTP_PORT"
} else {
    Warn "Services still starting. Open http://localhost:$NGINX_HTTP_PORT in your browser in a moment."
}

Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "    Zokai Station Free v$VERSION installed!" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Open in your browser:" -ForegroundColor White
Write-Host "    URL:      http://localhost:$NGINX_HTTP_PORT" -ForegroundColor Cyan
Write-Host "    Password: $VSCODE_PASSWORD" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Credentials also saved to: $BASE_DIR\access.txt" -ForegroundColor Gray
Write-Host ""

Log "INFO" "Install complete v$VERSION"
Read-Host "  Press Enter to close this window"

} # end finally
