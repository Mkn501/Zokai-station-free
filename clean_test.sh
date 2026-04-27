#!/bin/bash
# Clean Test Script for Zokai Station F&F
# Run this BEFORE testing to ensure a fresh install

echo "🧹 Cleaning up previous Zokai installation..."

# Stop all zokai containers
echo "  Stopping containers..."
docker ps -aq --filter "name=zokai" | xargs -r docker rm -f 2>/dev/null || true

# Remove zokai volumes
echo "  Removing volumes..."
docker volume ls -q --filter "name=zokai" | xargs -r docker volume rm 2>/dev/null || true

# Remove zokai and core networks (prevents IP overlap)
echo "  Removing networks..."
docker network ls -q --filter "name=zokai" | xargs -r docker network rm 2>/dev/null || true
docker network ls -q --filter "name=core_" | xargs -r docker network rm 2>/dev/null || true
docker network prune -f 2>/dev/null || true

# Clean local state
echo "  Cleaning local state..."
rm -f .env 2>/dev/null || true
rm -f "${SECRETS_DIR:-../secrets}"/*.txt 2>/dev/null || true
mkdir -p secrets

echo "✅ Cleanup complete!"
echo ""
echo "🚀 Starting fresh F&F installation..."
echo ""

# Run installer
chmod +x ff_installer.sh
./ff_installer.sh
