# zokai-launcher.ps1 — Zokai Station one-click launcher (Windows)
# Checks Docker → starts containers → opens Zokai in Chrome app mode
# Mirrors macOS zokai-launcher.template behavior exactly.
#
# Placeholders patched by installer:
#   __INSTALL_DIR__  → e.g. C:\Users\user\AppData\Local\ZokaiStation-free
#   __DATA_DIR__     → e.g. C:\Users\user\Documents\Zokai Station Free\.zokai
#
# Hazard mitigations applied (from 2026-04-14 retro):
#   #98:  cmd /c wrapper for all Docker commands (avoids PS stderr abort)
#   #100: WSL2-aware timeouts (60×5s = 5 min health check)
#   #101: PS1 twin of macOS launcher
#   #107: No Start-Job (not session-scoped — runs inline)
#   #112: No Start-Process -Wait (avoids process tree hang)

param(
    [string]$InstallDir = "__INSTALL_DIR__",
    [string]$DataDir    = "__DATA_DIR__"
)

$ErrorActionPreference = 'Continue'

# ─── Paths ────────────────────────────────────────────────────────────────────
$INSTALL_DIR = $InstallDir
$DATA_DIR    = $DataDir

# Read port from .env — check tier-specific env files (.env.free, .env.mkn) too.
function Read-EnvVar {
    param([string]$VarName)
    foreach ($envFile in @("$DATA_DIR\.env", "$INSTALL_DIR\.env", "$INSTALL_DIR\.env.free", "$INSTALL_DIR\.env.mkn")) {
        if (Test-Path $envFile) {
            $match = Select-String -Path $envFile -Pattern "^$VarName=(.+)" -ErrorAction SilentlyContinue
            if ($match) {
                return $match.Matches[0].Groups[1].Value.Trim()
            }
        }
    }
    return $null
}

$NGINX_PORT = Read-EnvVar "NGINX_HTTP_PORT"
if (-not $NGINX_PORT) {
    $NGINX_PORT = Read-EnvVar "VSCODE_PORT"
    if (-not $NGINX_PORT) { $NGINX_PORT = "8082" }
}
$URL = "http://localhost:$NGINX_PORT"

# ─── WinForms Progress Dialogs (non-blocking via separate runspace) ───────────
# Using runspaces instead of Start-Job (Lesson #107: Start-Job is session-scoped)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:progressForm = $null

function Show-Progress {
    param([string]$Message)
    Dismiss-Progress

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Zokai Station"
    $form.Size = New-Object System.Drawing.Size(420, 180)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Message
    $label.AutoSize = $false
    $label.Size = New-Object System.Drawing.Size(380, 80)
    $label.Location = New-Object System.Drawing.Point(15, 20)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.Controls.Add($label)

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Style = "Marquee"
    $progress.MarqueeAnimationSpeed = 30
    $progress.Size = New-Object System.Drawing.Size(380, 20)
    $progress.Location = New-Object System.Drawing.Point(15, 105)
    $form.Controls.Add($progress)

    $form.Show()
    $form.Refresh()
    $script:progressForm = $form
}

function Dismiss-Progress {
    if ($script:progressForm -and -not $script:progressForm.IsDisposed) {
        $script:progressForm.Close()
        $script:progressForm.Dispose()
    }
    $script:progressForm = $null
}

function Show-Error {
    param([string]$Message)
    Dismiss-Progress
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "Zokai Station",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

# ─── Guard: install dir must exist ────────────────────────────────────────────
if (-not (Test-Path $INSTALL_DIR)) {
    Show-Error "Zokai Station is not installed.`n`nExpected location:`n$INSTALL_DIR`n`nPlease run the installer first."
    exit 1
}

# ─── Step 1: Ensure Docker Desktop is running ─────────────────────────────────
# Lesson #98: Always use cmd /c wrapper to avoid PS stderr abort
$dockerInfo = cmd /c "docker info 2>nul"
if ($LASTEXITCODE -ne 0) {
    Show-Progress "Starting Docker Desktop...`n`nThis usually takes 10-30 seconds."
    # Try to start Docker Desktop
    $dockerExe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerExe) {
        Start-Process $dockerExe
    } else {
        # Fallback: try the standard Start Menu shortcut name
        Start-Process "Docker Desktop" -ErrorAction SilentlyContinue
    }

    # Poll up to 90s for Docker daemon to become ready
    $waited = 0
    do {
        Start-Sleep -Seconds 2
        $waited += 2
        cmd /c "docker info 2>nul" | Out-Null
        if ($waited -ge 90) {
            Show-Error "Docker Desktop did not start within 90 seconds.`n`nPlease start Docker Desktop manually and try again."
            exit 1
        }
        # Pump WinForms messages so progress bar animates
        [System.Windows.Forms.Application]::DoEvents()
    } while ($LASTEXITCODE -ne 0)
}

# ─── Step 2: Ensure containers are running ────────────────────────────────────
Set-Location $INSTALL_DIR

# Auto-detect tier-specific env file
$ENV_FILE = ""
foreach ($ef in @(".env.free", ".env.mkn", ".env")) {
    if (Test-Path "$INSTALL_DIR\$ef") { $ENV_FILE = $ef; break }
}
$composeEnv = if ($ENV_FILE) { "--env-file $ENV_FILE" } else { "" }

# Count running containers (Lesson #98: cmd /c wrapper)
$runningOutput = cmd /c "docker compose $composeEnv ps --status running --quiet 2>nul"
$running = if ($runningOutput) { ($runningOutput | Measure-Object -Line).Lines } else { 0 }

if ($running -lt 3) {
    Show-Progress "Starting Zokai services...`n`nThis takes 15-30 seconds on first start.`nWindows startup can take 1-2 minutes."
    # Lesson #98: cmd /c wrapper for docker compose
    cmd /c "docker compose $composeEnv up -d --remove-orphans 2>nul"
    if ($LASTEXITCODE -ne 0) {
        Show-Error "Failed to start Zokai services.`n`nCheck Docker Desktop for errors."
        exit 1
    }
    [System.Windows.Forms.Application]::DoEvents()
}

# ─── Step 3: Wait for Nginx to be reachable ───────────────────────────────────
# Lesson #100: WSL2 health checks need 5 min max (60×5s)
# We wait for ANY HTTP response (even 502 = splash page is working)
function Test-NginxResponding {
    try {
        $response = Invoke-WebRequest -Uri $URL -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
        return $true
    } catch [System.Net.WebException] {
        $webEx = $_.Exception
        if ($webEx.Response) {
            # Got an HTTP response (e.g. 502) — nginx is up, splash page works
            return $true
        }
        # Connection refused — nginx not up yet
        return $false
    } catch {
        return $false
    }
}

if (-not (Test-NginxResponding)) {
    Show-Progress "Waiting for Zokai to be ready...`n`nAlmost there! Windows startup takes 1-2 minutes."
    $attempts = 0
    do {
        Start-Sleep -Seconds 5
        $attempts++
        [System.Windows.Forms.Application]::DoEvents()
    } while (-not (Test-NginxResponding) -and $attempts -lt 60)  # 60×5s = 5 min max
}

Dismiss-Progress

# ─── Step 4: Open Zokai in Chrome app mode (borderless window) ────────────────
$chromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$chrome = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($chrome) {
    Start-Process $chrome "--app=$URL"
} else {
    # Fallback: default browser (no borderless mode)
    Start-Process $URL
}
