#!/bin/bash
# Zokai Station F&F Uninstaller
# Removes all containers, volumes, networks, and local data

echo "🗑️  Zokai Station F&F Uninstaller"
echo "=================================="
echo ""
echo "This will remove:"
echo "  - All Zokai Docker containers"
echo "  - All Zokai Docker volumes (WARNING: deletes indexed data)"
echo "  - All Zokai Docker networks"
echo "  - Local .env and secrets files"
echo ""
read -p "Are you sure you want to continue? [y/N]: " confirm

if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo "🛑 Stopping containers..."
docker compose down 2>/dev/null || true

echo "🗑️  Removing Zokai containers..."
containers=$(docker ps -aq --filter "name=zokai" 2>/dev/null)
[ -n "$containers" ] && docker rm -f $containers 2>/dev/null || true

echo "🗑️  Removing Zokai volumes..."
volumes=$(docker volume ls -q --filter "name=zokai" 2>/dev/null)
[ -n "$volumes" ] && docker volume rm $volumes 2>/dev/null || true

echo "🗑️  Removing Zokai networks..."
networks=$(docker network ls -q --filter "name=zokai" 2>/dev/null)
[ -n "$networks" ] && docker network rm $networks 2>/dev/null || true
networks=$(docker network ls -q --filter "name=core_" 2>/dev/null)
[ -n "$networks" ] && docker network rm $networks 2>/dev/null || true
docker network prune -f 2>/dev/null || true

echo "🗑️  Cleaning local files..."
rm -f .env 2>/dev/null || true
rm -f secrets/*.txt 2>/dev/null || true

echo ""
echo "✅ Zokai Station has been uninstalled."
echo ""
echo "To reinstall, run: ./ff_installer.sh"
