#!/bin/bash

# VPP Multi-Container Chain - Fresh VM Environment Setup Script
# 
# This script prepares a fresh Ubuntu/Debian VM with all necessary dependencies
# for the VPP Multi-Container Chain system including Docker, Python3, and required packages.
#
# Compatible with: Ubuntu 20.04+, Debian 11+
# Requirements: sudo access, internet connectivity
#
# Usage: sudo ./setup-environment.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { 
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        echo "Usage: sudo ./setup-environment.sh"
        exit 1
    fi
}

# Detect OS distribution
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        log_info "Detected OS: $OS $VER"
        
        case $ID in
            ubuntu)
                if [[ "$VERSION_ID" < "20.04" ]]; then
                    log_warning "Ubuntu 20.04+ recommended. Current version: $VERSION_ID"
                fi
                ;;
            debian)
                if [[ "$VERSION_ID" < "11" ]]; then
                    log_warning "Debian 11+ recommended. Current version: $VERSION_ID"
                fi
                ;;
            *)
                log_warning "Untested OS distribution: $ID. Proceeding with Ubuntu/Debian packages."
                ;;
        esac
    else
        log_error "Cannot detect OS distribution"
        exit 1
    fi
}

# Check system requirements
check_system_requirements() {
    log_header "System Requirements Check"
    
    # Check RAM
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 4 ]; then
        log_warning "System has ${TOTAL_RAM}GB RAM. 4GB+ recommended for VPP containers."
    else
        log_success "RAM: ${TOTAL_RAM}GB (sufficient)"
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [ "$AVAILABLE_SPACE" -lt 20 ]; then
        log_warning "Available disk space: ${AVAILABLE_SPACE}GB. 20GB+ recommended."
    else
        log_success "Disk space: ${AVAILABLE_SPACE}GB available (sufficient)"
    fi
    
    # Check CPU cores
    CPU_CORES=$(nproc)
    log_info "CPU cores: $CPU_CORES"
    if [ "$CPU_CORES" -lt 2 ]; then
        log_warning "System has $CPU_CORES CPU core(s). 2+ cores recommended for optimal performance."
    fi
}

# Update system packages
update_system() {
    log_header "Updating System Packages"
    
    # Update package list
    log_info "Updating package lists..."
    apt-get update -y
    
    # Upgrade existing packages
    log_info "Upgrading existing packages..."
    apt-get upgrade -y
    
    log_success "System packages updated"
}

# Install basic dependencies
install_basic_dependencies() {
    log_header "Installing Basic Dependencies"
    
    local packages=(
        "curl"
        "wget" 
        "gnupg"
        "lsb-release"
        "ca-certificates"
        "apt-transport-https"
        "software-properties-common"
        "git"
        "jq"
        "net-tools"
        "iproute2"
        "iptables"
        "bridge-utils"
        "tcpdump"
        "wireshark-common"
        "build-essential"
    )
    
    log_info "Installing basic packages: ${packages[*]}"
    apt-get install -y "${packages[@]}"
    
    log_success "Basic dependencies installed"
}

# Install Python3 and pip
install_python() {
    log_header "Installing Python3 and pip"
    
    # Install Python3 and related packages
    local python_packages=(
        "python3"
        "python3-pip"
        "python3-dev"
        "python3-venv"
        "python3-setuptools"
        "python3-wheel"
    )
    
    log_info "Installing Python packages: ${python_packages[*]}"
    apt-get install -y "${python_packages[@]}"
    
    # Verify Python installation
    PYTHON_VERSION=$(python3 --version 2>&1)
    PIP_VERSION=$(pip3 --version 2>&1)
    
    log_success "Python installed: $PYTHON_VERSION"
    log_success "pip installed: $PIP_VERSION"
    
    # Upgrade pip to latest version
    log_info "Upgrading pip to latest version..."
    python3 -m pip install --upgrade pip
    
    log_success "Python environment ready"
}

# Install Docker
install_docker() {
    log_header "Installing Docker"
    
    # Remove old Docker versions if they exist
    log_info "Removing old Docker versions..."
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    log_info "Adding Docker GPG key..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    log_info "Adding Docker repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package list with Docker repository
    apt-get update -y
    
    # Install Docker Engine
    log_info "Installing Docker Engine..."
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker service
    log_info "Starting Docker service..."
    systemctl start docker
    systemctl enable docker
    
    # Verify Docker installation
    DOCKER_VERSION=$(docker --version 2>&1)
    log_success "Docker installed: $DOCKER_VERSION"
    
    # Test Docker with hello-world
    log_info "Testing Docker installation..."
    if docker run --rm hello-world >/dev/null 2>&1; then
        log_success "Docker test successful"
    else
        log_warning "Docker test failed - may need system reboot"
    fi
}

# Install Python packages for VPP Chain
install_python_packages() {
    log_header "Installing Python Packages for VPP Chain"
    
    # Core Python packages required by the VPP chain
    local pip_packages=(
        "scapy>=2.4.5"          # Network packet manipulation
        "docker>=6.0.0"         # Docker API client
        "psutil>=5.8.0"         # System monitoring
        "netifaces>=0.11.0"     # Network interface info
        "ipaddress>=1.0.23"     # IP address manipulation
        "pyyaml>=6.0"           # YAML parsing
        "requests>=2.25.1"      # HTTP requests
        "click>=8.0.0"          # CLI framework
        "colorama>=0.4.4"       # Colored terminal output
        "tabulate>=0.9.0"       # Table formatting
    )
    
    log_info "Installing Python packages: ${pip_packages[*]}"
    
    # Install each package with error handling
    for package in "${pip_packages[@]}"; do
        log_info "Installing $package..."
        if python3 -m pip install "$package"; then
            log_success "✓ $package installed"
        else
            log_error "✗ Failed to install $package"
            exit 1
        fi
    done
    
    # Verify Scapy installation (critical for traffic generation)
    log_info "Verifying Scapy installation..."
    if python3 -c "from scapy.all import *; print('Scapy version:', conf.version)" 2>/dev/null; then
        log_success "Scapy verification successful"
    else
        log_error "Scapy verification failed"
        exit 1
    fi
    
    log_success "All Python packages installed successfully"
}

# Configure system for VPP networking
configure_system() {
    log_header "Configuring System for VPP Networking"
    
    # Enable IP forwarding
    log_info "Enabling IP forwarding..."
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
    sysctl -p
    
    # Configure Docker daemon for optimal networking
    log_info "Configuring Docker daemon..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "ip-forward": true,
    "iptables": true,
    "ip-masq": true
}
EOF
    
    # Restart Docker to apply configuration
    log_info "Restarting Docker with new configuration..."
    systemctl restart docker
    
    # Configure hugepages for VPP (optional but recommended)
    log_info "Configuring hugepages for VPP performance..."
    echo 'vm.nr_hugepages=512' >> /etc/sysctl.conf
    sysctl -p
    
    log_success "System configuration completed"
}

# Add user to docker group (if not root)
configure_user_permissions() {
    log_header "Configuring User Permissions"
    
    # Get the original user (before sudo)
    ORIGINAL_USER=${SUDO_USER:-$USER}
    
    if [ "$ORIGINAL_USER" != "root" ] && [ -n "$ORIGINAL_USER" ]; then
        log_info "Adding user '$ORIGINAL_USER' to docker group..."
        usermod -aG docker "$ORIGINAL_USER"
        log_success "User '$ORIGINAL_USER' added to docker group"
        log_warning "User needs to log out and log back in for group changes to take effect"
    else
        log_info "Running as root - no user group configuration needed"
    fi
}

# Verify installation
verify_installation() {
    log_header "Verifying Installation"
    
    # Check Python and packages
    log_info "Checking Python installation..."
    python3 --version
    pip3 --version
    
    # Check Docker
    log_info "Checking Docker installation..."
    docker --version
    docker compose version
    
    # Check key Python packages
    log_info "Checking critical Python packages..."
    python3 -c "import scapy; print('Scapy:', scapy.__version__)"
    python3 -c "import docker; print('Docker client:', docker.__version__)"
    python3 -c "import json; print('JSON support: OK')"
    
    # Check system networking
    log_info "Checking system networking capabilities..."
    if [ -f /proc/sys/net/ipv4/ip_forward ]; then
        IP_FORWARD=$(cat /proc/sys/net/ipv4/ip_forward)
        if [ "$IP_FORWARD" = "1" ]; then
            log_success "IP forwarding: enabled"
        else
            log_warning "IP forwarding: disabled"
        fi
    fi
    
    log_success "Installation verification completed"
}

# Create quick test script
create_test_script() {
    log_header "Creating Environment Test Script"
    
    cat > /home/${SUDO_USER:-root}/test-vpp-environment.sh << 'EOF'
#!/bin/bash
# Quick environment test for VPP Multi-Container Chain

echo "=== VPP Chain Environment Test ==="

# Test Python and packages
echo "Testing Python environment..."
python3 -c "
import sys
print(f'Python version: {sys.version}')

try:
    from scapy.all import *
    print('✓ Scapy import successful')
except Exception as e:
    print(f'✗ Scapy import failed: {e}')

try:
    import docker
    client = docker.from_env()
    print('✓ Docker client connection successful')
    print(f'  Docker version: {client.version()[\"Version\"]}')
except Exception as e:
    print(f'✗ Docker client failed: {e}')

try:
    import json, yaml, subprocess
    print('✓ Core packages available')
except Exception as e:
    print(f'✗ Core packages missing: {e}')
"

# Test Docker
echo -e "\nTesting Docker..."
if docker run --rm hello-world >/dev/null 2>&1; then
    echo "✓ Docker test successful"
else
    echo "✗ Docker test failed"
fi

# Test networking
echo -e "\nTesting networking capabilities..."
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    echo "✓ IP forwarding enabled"
else
    echo "✗ IP forwarding disabled"
fi

echo -e "\n=== Environment Test Complete ==="
EOF
    
    chmod +x /home/${SUDO_USER:-root}/test-vpp-environment.sh
    chown ${SUDO_USER:-root}:${SUDO_USER:-root} /home/${SUDO_USER:-root}/test-vpp-environment.sh 2>/dev/null || true
    
    log_success "Test script created: ~/test-vpp-environment.sh"
}

# Main execution
main() {
    log_header "VPP Multi-Container Chain - Environment Setup"
    log_info "Preparing fresh VM environment for VPP Multi-Container Chain system"
    log_info "This will install Docker, Python3, pip, Scapy, and all required dependencies"
    
    # Pre-flight checks
    check_root
    detect_os
    check_system_requirements
    
    # Installation steps
    update_system
    install_basic_dependencies
    install_python
    install_docker
    install_python_packages
    configure_system
    configure_user_permissions
    
    # Verification
    verify_installation
    create_test_script
    
    # Final summary
    log_header "Environment Setup Complete"
    log_success "VPP Multi-Container Chain environment is ready!"
    
    echo -e "\n${GREEN}Next steps:${NC}"
    echo "1. Log out and log back in (to apply docker group membership)"
    echo "2. Run the test script: ~/test-vpp-environment.sh"
    echo "3. Clone/navigate to VPP chain repository"
    echo "4. Run: sudo python3 src/main.py setup"
    echo "5. Test the chain: sudo python3 src/main.py test"
    
    echo -e "\n${BLUE}Quick commands to get started:${NC}"
    echo "  sudo python3 src/main.py setup          # Setup VPP chain"
    echo "  sudo python3 src/main.py test           # Test the chain"
    echo "  sudo ./quick-start.sh                   # Full validation"
    echo "  python3 src/main.py status              # Check status"
    
    log_success "Environment setup completed successfully!"
}

# Execute main function
main "$@"