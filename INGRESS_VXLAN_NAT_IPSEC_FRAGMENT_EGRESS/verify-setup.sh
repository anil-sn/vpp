#!/bin/bash
set -e

echo "========================================"
echo "VPP Multi-Container Chain Setup Verification"
echo "========================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_passed() {
    echo -e "${GREEN}✓ $1${NC}"
}

check_failed() {
    echo -e "${RED}✗ $1${NC}"
}

check_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check 1: System Requirements
check_info "Checking system requirements..."

if command -v docker >/dev/null 2>&1; then
    check_passed "Docker is installed"
    docker --version
else
    check_failed "Docker is not installed"
    exit 1
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    check_passed "Docker Compose is installed"
    docker compose version
elif command -v docker-compose >/dev/null 2>&1; then
    check_passed "Docker Compose (legacy) is installed"
    docker-compose --version
else
    check_failed "Docker Compose is not installed"
    exit 1
fi

if command -v python3 >/dev/null 2>&1; then
    check_passed "Python 3 is installed"
    python3 --version
else
    check_failed "Python 3 is not installed"
    exit 1
fi

# Check 2: Python dependencies
check_info "Checking Python dependencies..."

if python3 -c "import scapy" 2>/dev/null; then
    check_passed "Scapy is available"
else
    check_failed "Scapy is not installed. Install with: sudo apt-get install python3-scapy"
fi

# Check 3: Root privileges
check_info "Checking privileges..."
if [[ $EUID -eq 0 ]]; then
    check_passed "Running with root privileges"
else
    check_failed "Root privileges required for VPP operations. Use sudo."
    exit 1
fi

# Check 4: Required directories
check_info "Creating required directories..."
mkdir -p /tmp/vpp-logs
mkdir -p /tmp/packet-captures
check_passed "Required directories created"

# Check 5: File permissions
check_info "Checking file permissions..."
chmod +x src/configs/start-vpp.sh
chmod +x src/configs/*.sh
check_passed "Configuration scripts are executable"

# Check 6: Project structure
check_info "Verifying project structure..."

required_files=(
    "src/main.py"
    "src/configs/startup.conf"
    "src/configs/start-vpp.sh"
    "src/configs/ingress-config.sh"
    "src/configs/vxlan-config.sh"
    "src/configs/nat-config.sh"
    "src/configs/ipsec-config.sh"
    "src/configs/fragment-config.sh"
    "src/configs/gcp-config.sh"
    "src/containers/Dockerfile.base"
    "docker-compose.yml"
)

for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        check_passed "Found: $file"
    else
        check_failed "Missing: $file"
        exit 1
    fi
done

# Check 7: Docker daemon
check_info "Checking Docker daemon..."
if docker info >/dev/null 2>&1; then
    check_passed "Docker daemon is running"
else
    check_failed "Docker daemon is not running"
    exit 1
fi

# Check 8: Available memory
check_info "Checking system resources..."
total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
total_mem_gb=$((total_mem / 1024 / 1024))

if [[ $total_mem_gb -ge 8 ]]; then
    check_passed "Sufficient memory available: ${total_mem_gb}GB"
else
    check_failed "Insufficient memory. Recommend 8GB+, found: ${total_mem_gb}GB"
fi

# Check 9: Network configuration
check_info "Checking network configuration..."
if docker network ls | grep -q bridge; then
    check_passed "Docker bridge network available"
else
    check_failed "Docker bridge network not available"
fi

echo "========================================"
echo "Setup Verification Complete"
echo "========================================"

check_info "Ready to run VPP multi-container chain!"
echo ""
echo "Next steps:"
echo "1. Build and start: sudo python3 src/main.py setup"
echo "2. Check status:    python3 src/main.py status"
echo "3. Run tests:       sudo python3 src/main.py test"
echo "4. Run full test:   ./test-chain.sh"
echo ""
echo "For debugging:"
echo "- View logs:        docker logs <container-name>"
echo "- VPP CLI:          docker exec -it <container-name> vppctl"
echo "- Debug command:    sudo python3 src/main.py debug <container> \"<vpp-command>\""