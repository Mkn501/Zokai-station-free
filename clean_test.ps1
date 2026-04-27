<#
.SYNOPSIS
Clean Test Script for Zokai Station F&F (Windows)
Run this BEFORE testing to ensure a fresh install

.DESCRIPTION
Removes all Zokai containers, volumes, networks, and local secrets.
Then automatically triggering the installer.

.NOTES
Author: Zokai Team
#>

$ErrorActionPreference = 'Stop'

function Write-Color($text, $color) {
    Write-Host $text -ForegroundColor $color
}

Write-Host "Cleaning up previous Zokai installation..." -ForegroundColor Yellow

# Helper to run docker commands without erroring if empty
function Docker-Clean {
    param ($Cmd, $Filter)
    try {
        $ids = Invoke-Expression "$Cmd -q --filter `"name=$Filter`""
        if ($ids) {
            $ids | ForEach-Object { 
                $id = $_
                if ($Cmd -match "network") { docker network rm $id 2>$null }
                elseif ($Cmd -match "volume") { docker volume rm $id 2>$null }
                else { docker rm -f $id 2>$null }
            }
        }
    } catch {}
}

# Stop containers
Write-Host "  Stopping containers..."
Docker-Clean "docker ps -a" "zokai"

# Remove volumes
Write-Host "  Removing volumes..."
Docker-Clean "docker volume ls" "zokai"

# Remove networks
Write-Host "  Removing networks..."
Docker-Clean "docker network ls" "zokai"
Docker-Clean "docker network ls" "core_"
docker network prune -f 2>$null

# Clean local state
Write-Host "  Cleaning local state..."
if (Test-Path .env) { Remove-Item .env -Force -ErrorAction SilentlyContinue }
$secretsDir = if ($env:SECRETS_DIR) { $env:SECRETS_DIR } else { "../secrets" }
if (Test-Path "$secretsDir/*.txt") { Remove-Item "$secretsDir/*.txt" -Force -ErrorAction SilentlyContinue }
if (-not (Test-Path "secrets")) { New-Item -Path "secrets" -ItemType Directory -Force | Out-Null }

Write-Host "[OK] Cleanup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Starting fresh F&F installation..." -ForegroundColor Cyan
Write-Host ""

# Run installer
if (Test-Path "ff_installer.ps1") {
    & .\ff_installer.ps1
} else {
    Write-Host "Error: ff_installer.ps1 not found!" -ForegroundColor Red
}
