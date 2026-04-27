#!/bin/bash
# Troubleshooting Script for Fully Containerized Workstation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_step() {
  echo -e "${GREEN}=== $1 ===${NC}"
}

print_info() {
  echo -e "${YELLOW}$1${NC}"
}

print_error() {
  echo -e "${RED}Error: $1${NC}"
}

print_status() {
  echo -e "${BLUE}$1${NC}"
}

# Configuration
COMPOSE_FILE="docker-compose.yml"
PROJECT_NAME="workstation-distribution-v1"

# Troubleshooting functions
check_system_status() {
    print_step "Checking System Status"
    
    # Check Docker status
    if docker info > /dev/null 2>&1; then
        print_status "✓ Docker is running"
        docker --version
    else
        print_error "✗ Docker is not running"
        print_info "Start Docker and try again"
        return 1
    fi
    
    echo ""
    
    # Check Docker Compose status
    if command -v docker-compose &> /dev/null; then
        print_status "✓ Docker Compose is available"
        docker-compose --version
    elif docker compose version &> /dev/null; then
        print_status "✓ Docker Compose (plugin) is available"
        docker compose version
    else
        print_error "✗ Docker Compose is not available"
        return 1
    fi
    
    echo ""
    
    # Check container status
    print_info "Container Status:"
    if docker-compose -f "$COMPOSE_FILE" ps 2>/dev/null; then
        echo ""
    else
        print_error "✗ Failed to get container status"
        print_info "Check if docker-compose.yml exists and is valid"
    fi
}

check_network_connectivity() {
    print_step "Checking Network Connectivity"
    
    # Check if networks exist
    local networks=("frontend-network" "backend-network" "data-network" "management-network")
    for network in "${networks[@]}"; do
        if docker network ls | grep -q "$PROJECT_NAME\_$network"; then
            print_status "✓ Network exists: $network"
            
            # Check network details
            NETWORK_ID=$(docker network ls --filter name="$PROJECT_NAME\_$network" --format "{{.ID}}")
            SUBNET=$(docker network inspect "$NETWORK_ID" --format "{{range .IPAM.Config}}{{.Subnet}}{{end}}")
            print_info "  Subnet: $SUBNET"
        else
            print_error "✗ Network not found: $network"
        fi
    done
    
    echo ""
    
    # Check port conflicts
    print_info "Port Status:"
    local ports=("80" "443" "8080" "8000" "8001" "8002" "8003" "8004" "6333" "6379" "11434")
    for port in "${ports[@]}"; do
        if lsof -i :"$port" > /dev/null 2>&1; then
            PROCESS=$(lsof -i :"$port" | tail -n 1 | awk '{print $1}')
            print_error "✗ Port $port is in use by: $PROCESS"
        else
            print_status "✓ Port $port is available"
        fi
    done
}

check_service_health() {
    print_step "Checking Service Health"
    
    # Check if containers are running
    local containers=("vs-code" "nginx-proxy" "gptr-mcp" "qdrant" "redis")
    for container in "${containers[@]}"; do
        CONTAINER_NAME="$PROJECT_NAME-$container-1"
        
        if docker ps --format "table {{.Names}}" | grep -q "$CONTAINER_NAME"; then
            print_status "✓ Container is running: $container"
            
            # Check health status
            HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "no-healthcheck")
            if [ "$HEALTH" = "healthy" ]; then
                print_status "  Health: Healthy"
            elif [ "$HEALTH" = "unhealthy" ]; then
                print_error "  Health: Unhealthy"
            else
                print_info "  Health: No health check"
            fi
            
            # Check resource usage
            STATS=$(docker stats --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}" "$CONTAINER_NAME" 2>/dev/null | tail -n 1)
            if [ -n "$STATS" ]; then
                print_info "  Resources: $STATS"
            fi
        else
            print_error "✗ Container is not running: $container"
        fi
    done
    
    echo ""
    
    # Check service endpoints
    print_info "Service Endpoints:"
    
    # VS Code Server
    if curl -s http://localhost:8080 > /dev/null; then
        print_status "✓ VS Code Server is accessible"
    else
        print_error "✗ VS Code Server is not accessible"
    fi
    
    # NGINX Proxy
    if curl -s http://localhost:80 > /dev/null; then
        print_status "✓ NGINX Proxy is accessible"
    else
        print_error "✗ NGINX Proxy is not accessible"
    fi
    
    # Qdrant
    if curl -s http://localhost:6333 > /dev/null; then
        print_status "✓ Qdrant is accessible"
    else
        print_error "✗ Qdrant is not accessible"
    fi
    
    # Redis
    if docker-compose exec -T redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
        print_status "✓ Redis is accessible"
    else
        print_error "✗ Redis is not accessible"
    fi
}

check_logs() {
    print_step "Checking Service Logs"
    
    # Get recent logs from all services
    print_info "Recent container logs (last 20 lines):"
    echo ""
    
    local containers=("vs-code" "nginx-proxy" "gptr-mcp" "qdrant" "redis")
    for container in "${containers[@]}"; do
        CONTAINER_NAME="$PROJECT_NAME-$container-1"
        
        if docker ps --format "table {{.Names}}" | grep -q "$CONTAINER_NAME"; then
            print_info "Logs for $container:"
            docker logs --tail 5 "$CONTAINER_NAME" 2>&1 | sed 's/^/  /'
            echo ""
        fi
    done
}

check_permissions() {
    print_step "Checking File Permissions"
    
    # Check data directory permissions
    if [ -d "data" ]; then
        DATA_PERM=$(stat -c%a "data" 2>/dev/null || stat -f%A "data" 2>/dev/null)
        print_info "Data directory permissions: $DATA_PERM"
        
        # Test write permissions
        TEST_FILE="data/.permission_test"
        if touch "$TEST_FILE" 2>/dev/null; then
            print_status "✓ Data directory is writable"
            rm -f "$TEST_FILE"
        else
            print_error "✗ Data directory is not writable"
            print_info "Run: chmod -R $USER:$USER data"
        fi
    else
        print_error "✗ Data directory not found"
    fi
    
    echo ""
    
    # Check secrets directory permissions
    if [ -d "secrets" ]; then
        SECRETS_PERM=$(stat -c%a "secrets" 2>/dev/null || stat -f%A "secrets" 2>/dev/null)
        print_info "Secrets directory permissions: $SECRETS_PERM"
        
        if [ "$SECRETS_PERM" = "700" ]; then
            print_status "✓ Secrets directory has correct permissions"
        else
            print_error "✗ Secrets directory has incorrect permissions"
            print_info "Run: chmod 700 secrets"
        fi
    else
        print_error "✗ Secrets directory not found"
    fi
    
    echo ""
    
    # Check workspace directory permissions
    if [ -d "data/workspaces" ]; then
        WORKSPACE_PERM=$(stat -c%a "data/workspaces" 2>/dev/null || stat -f%A "data/workspaces" 2>/dev/null)
        print_info "Workspace directory permissions: $WORKSPACE_PERM"
        
        # Test write permissions
        TEST_FILE="data/workspaces/.permission_test"
        if touch "$TEST_FILE" 2>/dev/null; then
            print_status "✓ Workspace directory is writable"
            rm -f "$TEST_FILE"
        else
            print_error "✗ Workspace directory is not writable"
            print_info "Run: chmod -R $USER:$USER data/workspaces"
        fi
    else
        print_error "✗ Workspace directory not found"
    fi
}

check_gpu_support() {
    print_step "Checking GPU Support"
    
    # Check for NVIDIA drivers
    if command -v nvidia-smi &> /dev/null; then
        print_status "✓ NVIDIA drivers detected"
        nvidia-smi --query-gpu=name,driver_version --format=csv,noheader,nounits | sed 's/^/  /'
        
        # Check if embedding-server container is running
        EMBED_CONTAINER="$PROJECT_NAME-embedding-server-1"
        if docker ps --format "table {{.Names}}" | grep -q "$EMBED_CONTAINER"; then
            print_status "✓ Embedding server container is running"
        else
            print_info "⚠ Embedding server container is not running"
        fi
    else
        print_info "⚠ No NVIDIA drivers detected (CPU-only mode)"
    fi
}

check_disk_space() {
    print_step "Checking Disk Space"
    
    # Check overall disk usage
    df -h | grep -E "Filesystem|/dev/"
    
    echo ""
    
    # Check Docker space usage
    print_info "Docker space usage:"
    docker system df
    
    echo ""
    
    # Check workspace data size
    if [ -d "data" ]; then
        WORKSPACE_SIZE=$(du -sh data 2>/dev/null | cut -f1)
        print_info "Workspace data size: $WORKSPACE_SIZE"
    fi
    
    # Check Docker volumes size
    VOLUME_SIZE=$(docker system df --format "table {{.Type}}\t{{.Size}}" | grep "local volume" | tail -n 1 | awk '{print $3}')
    if [ -n "$VOLUME_SIZE" ]; then
        print_info "Docker volumes size: $VOLUME_SIZE"
    fi
}

provide_solutions() {
    print_step "Common Issues and Solutions"
    
    echo "1. Container won't start:"
    echo "   - Check logs: docker-compose logs [service-name]"
    echo "   - Check port conflicts: lsof -i :[port]"
    echo "   - Check disk space: df -h"
    echo ""
    
    echo "2. VS Code not accessible:"
    echo "   - Check if vs-code container is running: docker-compose ps"
    echo "   - Check NGINX proxy: docker-compose logs nginx-proxy"
    echo "   - Try accessing directly: http://localhost:8080"
    echo ""
    
    echo "3. MCP services not working:"
    echo "   - Check API keys: ./scripts/setup-secrets.sh"
    echo "   - Check service logs: docker-compose logs gptr-mcp"
    echo "   - Verify network connectivity: docker network ls"
    echo ""
    
    echo "4. Performance issues:"
    echo "   - Check resource usage: docker stats"
    echo "   - Check disk space: docker system df"
    echo "   - Restart services: docker-compose restart"
    echo ""
    
    echo "5. GPU not working:"
    echo "   - Check NVIDIA drivers: nvidia-smi"
    echo "   - Check NVIDIA Container Toolkit"
    echo "   - Verify GPU access in container"
    echo ""
    
    echo "6. Permission issues:"
    echo "   - Fix ownership: sudo chown -R \$USER:\$USER data/"
    echo "   - Fix permissions: chmod -R 755 data/"
    echo ""
    
    echo "For more help, check the documentation or create an issue on GitHub."
}

# Main menu
show_usage() {
    echo "Troubleshooting Script for Fully Containerized Workstation"
    echo ""
    echo "Usage: $0 {all|system|network|health|logs|permissions|gpu|disk|solutions}"
    echo ""
    echo "Commands:"
    echo "  all        - Run all checks (default)"
    echo "  system     - Check system status"
    echo "  network    - Check network connectivity"
    echo "  health     - Check service health"
    echo "  logs       - Check service logs"
    echo "  permissions- Check file permissions"
    echo "  gpu        - Check GPU support"
    echo "  disk       - Check disk space"
    echo "  solutions  - Show common issues and solutions"
    echo ""
    echo "Examples:"
    echo "  $0 all"
    echo "  $0 health"
    echo "  $0 logs"
    echo ""
}

# Main execution
case "${1:-all}" in
    all)
        check_system_status
        echo ""
        check_network_connectivity
        echo ""
        check_service_health
        echo ""
        check_permissions
        echo ""
        check_gpu_support
        echo ""
        check_disk_space
        echo ""
        provide_solutions
        ;;
    system)
        check_system_status
        ;;
    network)
        check_network_connectivity
        ;;
    health)
        check_service_health
        ;;
    logs)
        check_logs
        ;;
    permissions)
        check_permissions
        ;;
    gpu)
        check_gpu_support
        ;;
    disk)
        check_disk_space
        ;;
    solutions)
        provide_solutions
        ;;
    *)
        show_usage
        exit 1
        ;;
esac