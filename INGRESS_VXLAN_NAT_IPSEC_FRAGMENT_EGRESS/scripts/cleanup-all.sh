#!/bin/bash
# Complete cleanup script for VPP Multi-Container Chain

set -e

echo "========================================"
echo "VPP Multi-Container Chain Complete Cleanup"
echo "========================================"

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

# Stop containers using main.py
info "Stopping VPP chain containers..."
if sudo python3 src/main.py cleanup; then
    success "VPP chain cleanup completed"
else
    error "VPP chain cleanup failed, continuing with manual cleanup..."
fi

# Force stop any remaining containers
info "Force stopping any remaining VPP containers..."
containers=("chain-ingress" "chain-vxlan" "chain-nat" "chain-ipsec" "chain-fragment" "chain-gcp")

for container in "${containers[@]}"; do
    if docker ps -q -f name="$container" | grep -q .; then
        info "Force stopping $container..."
        docker stop "$container" 2>/dev/null || true
        docker rm -f "$container" 2>/dev/null || true
    fi
done

# Remove docker-compose services
info "Cleaning up docker-compose services..."
docker-compose down --volumes --remove-orphans 2>/dev/null || true

# Remove custom networks
info "Removing custom networks..."
networks=("ingress_vxlan_nat_ipsec_fragment_egress_underlay" 
          "ingress_vxlan_nat_ipsec_fragment_egress_chain-1-2"
          "ingress_vxlan_nat_ipsec_fragment_egress_chain-2-3"
          "ingress_vxlan_nat_ipsec_fragment_egress_chain-3-4" 
          "ingress_vxlan_nat_ipsec_fragment_egress_chain-4-5")

for network in "${networks[@]}"; do
    if docker network ls | grep -q "$network"; then
        info "Removing network: $network"
        docker network rm "$network" 2>/dev/null || true
    fi
done

# Clean up volumes
info "Removing volumes..."
docker volume prune -f 2>/dev/null || true

# Remove base image (optional)
read -p "Remove VPP base image? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    info "Removing VPP base image..."
    docker rmi vpp-chain-base:latest 2>/dev/null || true
    success "Base image removed"
fi

# Clean up temporary directories
info "Cleaning up temporary files..."
sudo rm -rf /tmp/vpp-logs/* 2>/dev/null || true
sudo rm -rf /tmp/packet-captures/* 2>/dev/null || true
success "Temporary files cleaned"

# System cleanup
info "Performing system cleanup..."
docker system prune -f 2>/dev/null || true

echo ""
success "Complete cleanup finished!"
echo ""
echo "System is now clean. To restart:"
echo "  sudo ./verify-setup.sh"
echo "  sudo python3 src/main.py setup"