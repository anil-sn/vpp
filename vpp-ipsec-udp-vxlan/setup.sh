#!/bin/bash
# setup.sh - VPP Test Environment Setup Script
#
# This script builds the complete test environment from a clean slate.
# It creates Docker containers, network interfaces, and configures VPP
# instances for VXLAN->NAT->IPsec testing.
#
# Architecture:
#   Host Bridge (br0: 192.168.1.1/24)
#   ├── aws_vpp (192.168.1.2/24) via veth pair
#   └── gcp_vpp (192.168.1.3/24) via veth pair
#
# Requirements:
#   - Ubuntu 20.04+ or Debian 11+
#   - Docker with privileged mode support
#   - Root/sudo access for network operations
#
# Author: Network Engineering Team
# Version: 2.0
# Last Updated: 2024

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

# Network configuration
AWS_VPP_IP="192.168.1.2"
GCP_VPP_IP="192.168.1.3"
BRIDGE_IP="192.168.1.1"
NETWORK_CIDR="192.168.1.0/24"

# Container names
AWS_CONTAINER="aws_vpp"
GCP_CONTAINER="gcp_vpp"
DOCKER_IMAGE="vpp-forwarder:latest"

# Interface names
AWS_PHY_IF="aws-phy"
AWS_BR_IF="aws-br"
GCP_PHY_IF="gcp-phy"
GCP_BR_IF="gcp-br"
BRIDGE_IF="br0"

# Timeouts and delays
CONTAINER_WAIT_TIMEOUT=30
VPP_WAIT_TIMEOUT=60
NETWORK_NAMESPACE_WAIT=5

# Logging configuration
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
LOG_FILE="/tmp/vpp_setup_$(date +%Y%m%d_%H%M%S).log"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Enhanced logging function with timestamps and levels
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Color coding for different log levels
    case "$level" in
        "DEBUG") color="\033[36m" ;;  # Cyan
        "INFO")  color="\033[32m" ;;  # Green
        "WARN")  color="\033[33m" ;;  # Yellow
        "ERROR") color="\033[31m" ;;  # Red
        *)       color="\033[0m"  ;;  # Default
    esac
    
    # Only show logs at or above the configured level
    case "$level" in
        "DEBUG") [[ "$LOG_LEVEL" == "DEBUG" ]] && echo -e "${color}[$timestamp] [$level] $message\033[0m" ;;
        "INFO")  [[ "$LOG_LEVEL" =~ ^(DEBUG|INFO)$ ]] && echo -e "${color}[$timestamp] [$level] $message\033[0m" ;;
        "WARN")  [[ "$LOG_LEVEL" =~ ^(DEBUG|INFO|WARN)$ ]] && echo -e "${color}[$timestamp] [$level] $message\033[0m" ;;
        "ERROR") echo -e "${color}[$timestamp] [$level] $message\033[0m" ;;
    esac
    
    # Always log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Check if running on macOS
check_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        log "ERROR" "This script requires a Linux host environment."
        echo
        echo "You are running on macOS, which doesn't support the required Linux networking commands:"
        echo "  - ip link (network interface management)"
        echo "  - ip addr (IP address assignment)"
        echo "  - bridge creation and veth pairs"
        echo "  - network namespace management"
        echo
        echo "Solutions:"
        echo "  1. Run on a Linux machine/VM (Ubuntu/Debian recommended)"
        echo "  2. Use a cloud Linux instance (AWS EC2, Google Cloud, etc.)"
        echo "  3. Set up a Linux VM on your Mac using VirtualBox or VMware"
        echo "  4. Use WSL2 on Windows if available"
        echo
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check if running as root/sudo
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Check for required commands
    local required_commands=("docker" "ip" "bridge")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "Required command '$cmd' not found"
            log "INFO" "Install with: sudo apt install -y docker.io iproute2 bridge-utils"
            exit 1
        fi
    done
    
    # Check Docker service
    if ! systemctl is-active --quiet docker; then
        log "WARN" "Docker service is not running, attempting to start..."
        systemctl start docker || {
            log "ERROR" "Failed to start Docker service"
            exit 1
        }
    fi
    
    # Check if Docker image exists
    if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
        log "ERROR" "Docker image '$DOCKER_IMAGE' not found"
        log "INFO" "Build the image first with: docker build -t $DOCKER_IMAGE ."
        exit 1
    fi
    
    log "INFO" "System requirements check completed successfully"
}

# Clean up existing network interfaces
cleanup_network_interfaces() {
    log "INFO" "Cleaning up existing network interfaces..."
    
    # Remove existing veth pairs
    for iface in "$AWS_PHY_IF" "$AWS_BR_IF" "$GCP_PHY_IF" "$GCP_BR_IF"; do
        if ip link show "$iface" >/dev/null 2>&1; then
            log "DEBUG" "Removing existing interface: $iface"
            ip link delete "$iface" 2>/dev/null || log "WARN" "Failed to remove $iface (may not exist)"
        fi
    done
    
    # Remove existing bridge
    if ip link show "$BRIDGE_IF" >/dev/null 2>&1; then
        log "DEBUG" "Removing existing bridge: $BRIDGE_IF"
        ip link delete "$BRIDGE_IF" 2>/dev/null || log "WARN" "Failed to remove $BRIDGE_IF (may not exist)"
    fi
    
    log "INFO" "Network interface cleanup completed"
}

# Create and configure host bridge
setup_host_bridge() {
    log "INFO" "Setting up host bridge network..."
    
    # Create bridge interface
    log "DEBUG" "Creating bridge interface: $BRIDGE_IF"
    if ! ip link add name "$BRIDGE_IF" type bridge; then
        log "ERROR" "Failed to create bridge interface"
        exit 1
    fi
    
    # Enable bridge
    log "DEBUG" "Enabling bridge interface"
    if ! ip link set "$BRIDGE_IF" up; then
        log "ERROR" "Failed to enable bridge interface"
        exit 1
    fi
    
    # Assign IP address to bridge
    log "DEBUG" "Assigning IP address $BRIDGE_IP/24 to bridge"
    if ! ip addr add "$BRIDGE_IP/24" dev "$BRIDGE_IF"; then
        log "ERROR" "Failed to assign IP address to bridge"
        exit 1
    fi
    
    log "INFO" "Host bridge setup completed successfully"
}

# Create and start Docker containers
create_docker_containers() {
    log "INFO" "Creating Docker containers..."
    
    # Start AWS VPP container
    log "DEBUG" "Starting AWS VPP container: $AWS_CONTAINER"
    if ! docker run -d --name "$AWS_CONTAINER" --privileged \
        -v "$(pwd)/aws-startup.conf:/etc/vpp/startup.conf" \
        -it "$DOCKER_IMAGE"; then
        log "ERROR" "Failed to start AWS VPP container"
        exit 1
    fi
    
    # Start GCP VPP container
    log "DEBUG" "Starting GCP VPP container: $GCP_CONTAINER"
    if ! docker run -d --name "$GCP_CONTAINER" --privileged \
        -v "$(pwd)/gcp-startup.conf:/etc/vpp/startup.conf" \
        -it "$DOCKER_IMAGE"; then
        log "ERROR" "Failed to start GCP VPP container"
        exit 1
    fi
    
    log "INFO" "Docker containers created successfully"
}

# Wait for container network namespaces to be ready
wait_for_network_namespaces() {
    log "INFO" "Waiting for container network namespaces..."
    
    # Wait for AWS container
    log "DEBUG" "Waiting for $AWS_CONTAINER network namespace..."
    local aws_pid
    local timeout_counter=0
    
    while [[ $timeout_counter -lt $NETWORK_NAMESPACE_WAIT ]]; do
        aws_pid=$(docker inspect -f '{{.State.Pid}}' "$AWS_CONTAINER" 2>/dev/null)
        if [[ -n "$aws_pid" && -f "/proc/$aws_pid/ns/net" ]]; then
            log "DEBUG" "$AWS_CONTAINER network namespace ready (PID: $aws_pid)"
            break
        fi
        sleep 1
        ((timeout_counter++))
    done
    
    if [[ $timeout_counter -ge $NETWORK_NAMESPACE_WAIT ]]; then
        log "ERROR" "Timeout waiting for $AWS_CONTAINER network namespace"
        exit 1
    fi
    
    # Wait for GCP container
    log "DEBUG" "Waiting for $GCP_CONTAINER network namespace..."
    local gcp_pid
    timeout_counter=0
    
    while [[ $timeout_counter -lt $NETWORK_NAMESPACE_WAIT ]]; do
        gcp_pid=$(docker inspect -f '{{.State.Pid}}' "$GCP_CONTAINER" 2>/dev/null)
        if [[ -n "$gcp_pid" && -f "/proc/$gcp_pid/ns/net" ]]; then
            log "DEBUG" "$GCP_CONTAINER network namespace ready (PID: $gcp_pid)"
            break
        fi
        sleep 1
        ((timeout_counter++))
    done
    
    if [[ $timeout_counter -ge $NETWORK_NAMESPACE_WAIT ]]; then
        log "ERROR" "Timeout waiting for $GCP_CONTAINER network namespace"
        exit 1
    fi
    
    # Store PIDs for later use
    AWS_PID="$aws_pid"
    GCP_PID="$gcp_pid"
    
    log "INFO" "All container network namespaces are ready"
}

# Setup network plumbing for AWS container
setup_aws_networking() {
    log "INFO" "Setting up AWS container networking..."
    
    # Create veth pair for AWS
    log "DEBUG" "Creating veth pair: $AWS_PHY_IF <-> $AWS_BR_IF"
    if ! ip link add "$AWS_PHY_IF" type veth peer name "$AWS_BR_IF"; then
        log "ERROR" "Failed to create veth pair for AWS"
        exit 1
    fi
    
    # Move one end to container namespace
    log "DEBUG" "Moving $AWS_PHY_IF to container namespace (PID: $AWS_PID)"
    if ! ip link set "$AWS_PHY_IF" netns "$AWS_PID"; then
        log "ERROR" "Failed to move $AWS_PHY_IF to container namespace"
        exit 1
    fi
    
    # Add bridge end to bridge
    log "DEBUG" "Adding $AWS_BR_IF to bridge $BRIDGE_IF"
    if ! ip link set "$AWS_BR_IF" master "$BRIDGE_IF"; then
        log "ERROR" "Failed to add $AWS_BR_IF to bridge"
        exit 1
    fi
    
    # Enable bridge end
    log "DEBUG" "Enabling $AWS_BR_IF"
    if ! ip link set "$AWS_BR_IF" up; then
        log "ERROR" "Failed to enable $AWS_BR_IF"
        exit 1
    fi
    
    log "INFO" "AWS container networking setup completed"
}

# Setup network plumbing for GCP container
setup_gcp_networking() {
    log "INFO" "Setting up GCP container networking..."
    
    # Create veth pair for GCP
    log "DEBUG" "Creating veth pair: $GCP_PHY_IF <-> $GCP_BR_IF"
    if ! ip link add "$GCP_PHY_IF" type veth peer name "$GCP_BR_IF"; then
        log "ERROR" "Failed to create veth pair for GCP"
        exit 1
    fi
    
    # Move one end to container namespace
    log "DEBUG" "Moving $GCP_PHY_IF to container namespace (PID: $GCP_PID)"
    if ! ip link set "$GCP_PHY_IF" netns "$GCP_PID"; then
        log "ERROR" "Failed to move $GCP_PHY_IF to container namespace"
        exit 1
    fi
    
    # Add bridge end to bridge
    log "DEBUG" "Adding $GCP_BR_IF to bridge $BRIDGE_IF"
    if ! ip link set "$GCP_BR_IF" master "$BRIDGE_IF"; then
        log "ERROR" "Failed to add $GCP_BR_IF to bridge"
        exit 1
    fi
    
    # Enable bridge end
    log "DEBUG" "Enabling $GCP_BR_IF"
    if ! ip link set "$GCP_BR_IF" up; then
        log "ERROR" "Failed to enable $GCP_BR_IF"
        exit 1
    fi
    
    log "INFO" "GCP container networking setup completed"
}

# Wait for VPP to initialize in containers
wait_for_vpp_initialization() {
    log "INFO" "Waiting for VPP initialization in containers..."
    
    for container in "$AWS_CONTAINER" "$GCP_CONTAINER"; do
        log "DEBUG" "Waiting for VPP in $container..."
        local timeout_counter=0
        
        while [[ $timeout_counter -lt $VPP_WAIT_TIMEOUT ]]; do
            if docker exec "$container" test -S /run/vpp/cli.sock 2>/dev/null; then
                log "DEBUG" "VPP in $container is ready"
                break
            fi
            sleep 1
            ((timeout_counter++))
        done
        
        if [[ $timeout_counter -ge $VPP_WAIT_TIMEOUT ]]; then
            log "ERROR" "Timeout waiting for VPP in $container"
            exit 1
        fi
    done
    
    log "INFO" "VPP initialization completed in all containers"
}

# Apply VPP configurations
apply_vpp_configurations() {
    log "INFO" "Applying VPP configurations..."
    
    # Copy configuration scripts to containers
    log "DEBUG" "Copying configuration scripts to containers..."
    if ! docker cp aws-config.sh "$AWS_CONTAINER:/root/aws-config.sh"; then
        log "ERROR" "Failed to copy aws-config.sh to $AWS_CONTAINER"
        exit 1
    fi
    
    if ! docker cp gcp-config.sh "$GCP_CONTAINER:/root/gcp-config.sh"; then
        log "ERROR" "Failed to copy gcp-config.sh to $GCP_CONTAINER"
        exit 1
    fi
    
    # Execute AWS configuration
    log "DEBUG" "Executing AWS VPP configuration..."
    if ! docker exec "$AWS_CONTAINER" bash /root/aws-config.sh; then
        log "ERROR" "Failed to execute AWS VPP configuration"
        exit 1
    fi
    
    # Execute GCP configuration
    log "DEBUG" "Executing GCP VPP configuration..."
    if ! docker exec "$GCP_CONTAINER" bash /root/gcp-config.sh; then
        log "ERROR" "Failed to execute GCP VPP configuration"
        exit 1
    fi
    
    log "INFO" "VPP configurations applied successfully"
}

# Verify network connectivity
verify_network_connectivity() {
    log "INFO" "Verifying network connectivity..."
    
    # Test bridge connectivity
    if ping -c 1 -W 2 "$BRIDGE_IP" >/dev/null 2>&1; then
        log "INFO" "Bridge connectivity: SUCCESS"
    else
        log "WARN" "Bridge connectivity: FAILED (this may be normal)"
    fi
    
    # Test container reachability (basic check)
    if docker exec "$AWS_CONTAINER" ping -c 1 -W 2 "$GCP_VPP_IP" >/dev/null 2>&1; then
        log "INFO" "Container-to-container connectivity: SUCCESS"
    else
        log "WARN" "Container-to-container connectivity: FAILED (may need VPP config)"
    fi
    
    log "INFO" "Network connectivity verification completed"
}

# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================

main() {
    log "INFO" "Starting VPP test environment setup"
    log "INFO" "Log file: $LOG_FILE"
    
    # Check OS compatibility first
    check_os
    
    # Check system requirements
    check_requirements
    
    # Display configuration
    log "INFO" "Configuration:"
    log "INFO" "  AWS VPP IP: $AWS_VPP_IP"
    log "INFO" "  GCP VPP IP: $GCP_VPP_IP"
    log "INFO" "  Bridge IP: $BRIDGE_IP"
    log "INFO" "  Network: $NETWORK_CIDR"
    log "INFO" "  Log Level: $LOG_LEVEL"
    
    # Step 1: Clean up existing network interfaces
    cleanup_network_interfaces
    
    # Step 2: Setup host bridge
    setup_host_bridge
    
    # Step 3: Create Docker containers
    create_docker_containers
    
    # Step 4: Wait for network namespaces
    wait_for_network_namespaces
    
    # Step 5: Setup container networking
    setup_aws_networking
    setup_gcp_networking
    
    # Step 6: Wait for VPP initialization
    wait_for_vpp_initialization
    
    # Step 7: Apply VPP configurations
    apply_vpp_configurations
    
    # Step 8: Verify network connectivity
    verify_network_connectivity
    
    log "INFO" "VPP test environment setup completed successfully"
    echo "--- Setup complete! ---"
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi