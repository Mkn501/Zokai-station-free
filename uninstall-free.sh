#!/bin/bash
# Zokai Station Free — Uninstaller
# Removes ONLY Free-tier containers, volumes, networks, images, and data
# Does NOT touch Pro/MKN (zokai-mkn-*) installations
#
# Auto-detects paths from its own location and .env.free

set -eo pipefail

# ─── Auto-detect install directory (this script lives inside it) ─────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR"

# ─── Read paths from .env.free ───────────────────────────────────────────────
ENV_FILE="$INSTALL_DIR/.env.free"
if [ -f "$ENV_FILE" ]; then
    BASE_DIR=$(grep "^BASE_DIR=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "")
    WORKSPACE_DIR=$(grep "^WORKSPACE_DIR=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "")
    DATA_DIR=$(grep "^DATA_DIR=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "")
    INSTANCE=$(grep "^COMPOSE_PROJECT_NAME=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "zokai-free")
else
    echo "⚠️  Could not find .env.free at $ENV_FILE"
    echo "   Falling back to default paths..."
    BASE_DIR="$HOME/Documents/Zokai Station Free"
    WORKSPACE_DIR="$BASE_DIR/workspace"
    DATA_DIR="$BASE_DIR/.zokai"
    INSTANCE="zokai-free"
fi

# Launcher app is always in ~/Applications
LAUNCHER_APP="$HOME/Applications/Zokai Station Free.app"

echo ""
echo "🗑️  Zokai Station Free — Uninstaller"
echo "======================================"
echo ""
echo "Detected paths:"
echo "  ✦ Install dir:  $INSTALL_DIR"
echo "  ✦ Workspace:    ${WORKSPACE_DIR:-not set}"
echo "  ✦ Data dir:     ${DATA_DIR:-not set}"
echo "  ✦ Base dir:     ${BASE_DIR:-not set}"
echo "  ✦ Launcher:     $LAUNCHER_APP"
echo "  ✦ Docker prefix: $INSTANCE"
echo ""
echo "This will remove:"
echo "  ✦ All ${INSTANCE}-* Docker containers, volumes, networks, and images"
echo "  ✦ The install directory and launcher app"
echo ""
echo "⚠️  Your Pro/MKN installation will NOT be affected."
echo ""
read -p "Are you sure you want to continue? [y/N]: " confirm

if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""

# ─── Step 1: Stop and remove containers ──────────────────────────────────────
echo "🛑 Stopping Free tier containers..."
if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cd "$INSTALL_DIR"
    docker compose --env-file ".env.free" -f docker-compose.yml down --volumes --remove-orphans 2>/dev/null || true
    cd "$HOME"
fi

echo "🗑️  Removing any remaining ${INSTANCE} containers..."
containers=$(docker ps -aq --filter "name=${INSTANCE}" 2>/dev/null || true)
[ -n "$containers" ] && docker rm -f $containers 2>/dev/null || true

# ─── Step 2: Remove volumes ─────────────────────────────────────────────────
echo "🗑️  Removing ${INSTANCE} volumes..."
volumes=$(docker volume ls -q --filter "name=${INSTANCE}" 2>/dev/null || true)
[ -n "$volumes" ] && docker volume rm $volumes 2>/dev/null || true

# ─── Step 3: Remove networks ────────────────────────────────────────────────
echo "🗑️  Removing ${INSTANCE} networks..."
networks=$(docker network ls -q --filter "name=${INSTANCE}" 2>/dev/null || true)
[ -n "$networks" ] && docker network rm $networks 2>/dev/null || true

# ─── Step 4: Remove Docker images ───────────────────────────────────────────
echo "🗑️  Removing ${INSTANCE} images..."
images=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "${INSTANCE}" || true)
if [ -n "$images" ]; then
    echo "$images" | xargs docker rmi -f 2>/dev/null || true
fi

# ─── Step 5: Remove local files ─────────────────────────────────────────────
echo "🗑️  Removing local files..."

# Launcher app
if [ -d "$LAUNCHER_APP" ]; then
    rm -rf "$LAUNCHER_APP"
    echo "  ✓ Removed launcher app"
fi

# Workspace & data (ask first)
if [ -n "$BASE_DIR" ] && [ -d "$BASE_DIR" ]; then
    echo ""
    echo "📁 Your workspace is at: $BASE_DIR"
    echo "   This contains your notes, outputs, and workspace files."
    echo ""
    read -p "   Also remove workspace and all data? [y/N]: " rm_data
    if [ "$rm_data" = "y" ] || [ "$rm_data" = "Y" ]; then
        rm -rf "$BASE_DIR"
        echo "  ✓ Removed workspace and data"
    else
        echo "  ⏭  Kept workspace (your files are preserved for reinstall)"
    fi
fi

# Install directory (last, since the script lives here)
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "  ✓ Removed install directory"
fi

echo ""
echo "✅ Zokai Station Free has been uninstalled."
echo ""
echo "Your Pro/MKN installation was not touched."
echo "To reinstall, double-click the DMG and run the installer."
echo ""
