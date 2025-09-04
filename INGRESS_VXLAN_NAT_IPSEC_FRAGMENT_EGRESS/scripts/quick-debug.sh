#!/bin/bash
# Quick Debug Script for VPP Multi-Container Chain

set -e

echo "========================================"
echo "VPP Multi-Container Chain Quick Debug"
echo "========================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if containers are running
info "Checking container status..."
if docker ps | grep -q chain-; then
    success "VPP containers are running"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep chain-
else
    error "No VPP containers found running"
    echo "Run: sudo python3 src/main.py setup"
    exit 1
fi

echo ""
info "Quick VPP status check for each container..."

containers=("chain-ingress" "chain-vxlan" "chain-nat" "chain-ipsec" "chain-fragment" "chain-gcp")

for container in "${containers[@]}"; do
    echo ""
    echo "--- $container ---"
    
    # Check if container is running
    if docker ps | grep -q "$container"; then
        success "$container is running"
        
        # Check VPP responsiveness
        if docker exec "$container" vppctl show version >/dev/null 2>&1; then
            success "VPP is responsive in $container"
            
            # Show interface summary
            echo "Interfaces:"
            docker exec "$container" vppctl show interface addr | head -10
            
        else
            error "VPP not responsive in $container"
        fi
    else
        error "$container is not running"
    fi
done

echo ""
info "Network connectivity test..."
if python3 -c "
import subprocess
try:
    # Test ping between containers
    result = subprocess.run(['docker', 'exec', 'chain-ingress', 'ping', '-c', '1', '10.1.1.2'], 
                          capture_output=True, timeout=5)
    if result.returncode == 0:
        print('✓ Basic connectivity working')
    else:
        print('✗ Connectivity issues detected')
except:
    print('✗ Connectivity test failed')
"; then
    success "Network test completed"
else
    error "Network test failed"
fi

echo ""
info "VPP trace status..."
for container in "${containers[@]}"; do
    if docker ps | grep -q "$container"; then
        echo "--- $container trace ---"
        docker exec "$container" vppctl show trace | head -5 || echo "No trace data"
    fi
done

echo ""
info "Resource usage..."
echo "Memory usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep chain-

echo ""
echo "========================================"
echo "Quick Debug Complete"
echo "========================================"
echo ""
echo "For detailed debugging:"
echo "  sudo python3 src/main.py debug <container> \"<vpp-command>\""
echo ""
echo "For full testing:"
echo "  ./test-chain.sh"