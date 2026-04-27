<#
.SYNOPSIS
Zokai Station Free Tier — Windows Uninstaller

.DESCRIPTION
Removes all Zokai Free containers, volumes, networks, and optionally local data.
Run via uninstall-free.bat (double-click) or directly in PowerShell.

.NOTES
Version:   4.0.0-free
#>

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Red
Write-Host "    Zokai Station Free -- Uninstaller" -ForegroundColor Red
Write-Host "  ============================================================" -ForegroundColor Red
Write-Host ""
Write-Host "  This will remove:" -ForegroundColor White
Write-Host "    - All Zokai Free Docker containers" -ForegroundColor Gray
Write-Host "    - All Zokai Free Docker volumes (indexed data)" -ForegroundColor Gray
Write-Host "    - All Zokai Free Docker networks" -ForegroundColor Gray
Write-Host ""

# Detect data directories from .env.free
$INSTALL_DIR = "$env:USERPROFILE\AppData\Local\ZokaiStation-free"
$BASE_DIR = ""
$DATA_DIR = ""

if (Test-Path "$INSTALL_DIR\.env.free") {
    $envContent = Get-Content "$INSTALL_DIR\.env.free" -ErrorAction SilentlyContinue
    $BASE_DIR = ($envContent | Where-Object { $_ -match "^BASE_DIR=" } | Select-Object -First 1) -replace "^BASE_DIR=",""
    $DATA_DIR = ($envContent | Where-Object { $_ -match "^DATA_DIR=" } | Select-Object -First 1) -replace "^DATA_DIR=",""
}

if ($BASE_DIR) {
    Write-Host "  Also optionally:" -ForegroundColor Yellow
    Write-Host "    - Application files: $INSTALL_DIR" -ForegroundColor Gray
    Write-Host "    - Internal data:     $DATA_DIR" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Your workspace (notes, outputs) at:" -ForegroundColor White
    Write-Host "    $BASE_DIR\workspace" -ForegroundColor Cyan
    Write-Host "  will NOT be deleted." -ForegroundColor White
}
Write-Host ""

$confirm = Read-Host "  Are you sure you want to uninstall? [y/N]"
if ($confirm -ne "y" -and $confirm -ne "Y") {
    Write-Host "  Uninstall cancelled."
    exit 0
}

Write-Host ""

# Stop and remove containers
Write-Host "  Stopping containers..." -ForegroundColor Yellow
if (Test-Path "$INSTALL_DIR\.env.free") {
    Set-Location $INSTALL_DIR -ErrorAction SilentlyContinue
    cmd /c "docker compose --env-file .env.free -f docker-compose.yml down --volumes --remove-orphans 2>nul"
} else {
    cmd /c "docker compose down 2>nul"
}

Write-Host "  Removing Zokai Free containers..." -ForegroundColor Yellow
$containers = docker ps -aq --filter "name=zokai-free" 2>$null
if ($containers) {
    $containers | ForEach-Object { cmd /c "docker rm -f $_ 2>nul" }
}

Write-Host "  Removing Zokai Free volumes..." -ForegroundColor Yellow
$volumes = docker volume ls -q --filter "name=zokai-free" 2>$null
if ($volumes) {
    $volumes | ForEach-Object { cmd /c "docker volume rm $_ 2>nul" }
}

Write-Host "  Removing Zokai Free networks..." -ForegroundColor Yellow
$networks = docker network ls -q --filter "name=zokai-free" 2>$null
if ($networks) {
    $networks | ForEach-Object { cmd /c "docker network rm $_ 2>nul" }
}

Write-Host "  Removing Zokai Free images..." -ForegroundColor Yellow
$images = docker images --format '{{.Repository}}:{{.Tag}}' 2>$null | Where-Object { $_ -match "zokai-free" }
if ($images) {
    $images | ForEach-Object { cmd /c "docker rmi -f $_ 2>nul" }
}

Write-Host "  Pruning Docker build cache..." -ForegroundColor Yellow
cmd /c "docker builder prune -af 2>nul"

# Clean application files
Write-Host "  Removing application files..." -ForegroundColor Yellow
if (Test-Path $INSTALL_DIR) {
    Remove-Item $INSTALL_DIR -Recurse -Force -ErrorAction SilentlyContinue
}

# Clean internal data (secrets, qdrant, redis, etc.) but NOT workspace
if ($DATA_DIR -and (Test-Path $DATA_DIR)) {
    Write-Host "  Removing internal data ($DATA_DIR)..." -ForegroundColor Yellow
    Remove-Item $DATA_DIR -Recurse -Force -ErrorAction SilentlyContinue
}

# Remove access.txt from BASE_DIR
if ($BASE_DIR) {
    Remove-Item "$BASE_DIR\access.txt" -Force -ErrorAction SilentlyContinue
    Remove-Item "$BASE_DIR\Uninstall Zokai Station.bat" -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "  [OK] Zokai Station Free has been uninstalled." -ForegroundColor Green
Write-Host ""
if ($BASE_DIR) {
    Write-Host "  Your workspace is preserved at:" -ForegroundColor White
    Write-Host "    $BASE_DIR\workspace" -ForegroundColor Cyan
    Write-Host ""
}
Write-Host "  To reinstall, extract the zip again and run install-free.bat" -ForegroundColor Gray
Write-Host ""
Read-Host "  Press Enter to close"
