#!/bin/bash
#
# cleanup.sh - VPP Test Environment Cleanup Script
#
# This script is responsible for tearing down all components of the test environment.
# It is designed to be idempotent, meaning it can be run multiple times without
# causing errors if the resources it tries to delete are already gone.
# It must be run with sudo because it modifies host network interfaces.
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

# Container names
AWS_CONTAINER="aws_vpp"
GCP_CONTAINER="gcp_vpp"

# Interface names
AWS_BR_IF="aws-br"
GCP_BR_IF="gcp-br"
BRIDGE_IF="br0"

# Timeouts and delays
CONTAINER_STOP_TIMEOUT=10
CONTAINER_REMOVE_TIMEOUT=5

# Logging configuration
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
LOG_FILE="/tmp/vpp_cleanup_$(date +%Y%m%d_%H%M%S).log"

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
        echo "  - bridge deletion"
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
    local required_commands=("docker" "ip")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "Required command '$cmd' not found"
            log "INFO" "Install with: sudo apt install -y docker.io iproute2"
            exit 1
        fi
    done
    
    log "INFO" "System requirements check completed successfully"
}

# Stop and remove Docker containers
cleanup_docker_containers() {
    log "INFO" "Cleaning up Docker containers..."
    
    local containers=("$AWS_CONTAINER" "$GCP_CONTAINER")
    
    for container in "${containers[@]}"; do
        if docker ps -q -f name="^${container}$" >/dev/null 2>&1; then
            log "DEBUG" "Stopping container: $container"
            if docker stop "$container" >/dev/null 2>&1; then
                log "DEBUG" "Container $container stopped successfully"
            else
                log "WARN" "Failed to stop container $container"
            fi
        else
            log "DEBUG" "Container $container is not running"
        fi
        
        if docker ps -a -q -f name="^${container}$" >/dev/null 2>&1; then
            log "DEBUG" "Removing container: $container"
            if docker rm "$container" >/dev/null 2>&1; then
                log "DEBUG" "Container $container removed successfully"
            else
                log "WARN" "Failed to remove container $container"
            fi
        else
            log "DEBUG" "Container $container does not exist"
        fi
    done
    
    log "INFO" "Docker container cleanup completed"
}

# Remove host-side network interfaces
cleanup_network_interfaces() {
    log "INFO" "Cleaning up host network interfaces..."
    
    # Remove veth pair interfaces
    local veth_interfaces=("$AWS_BR_IF" "$GCP_BR_IF")
    
    for iface in "${veth_interfaces[@]}"; do
        if ip link show "$iface" >/dev/null 2>&1; then
            log "DEBUG" "Removing veth interface: $iface"
            if ip link delete "$iface" >/dev/null 2>&1; then
                log "DEBUG" "Interface $iface removed successfully"
            else
                log "WARN" "Failed to remove interface $iface"
            fi
        else
            log "DEBUG" "Interface $iface does not exist"
        fi
    done
    
    # Remove bridge interface
    if ip link show "$BRIDGE_IF" >/dev/null 2>&1; then
        log "DEBUG" "Removing bridge interface: $BRIDGE_IF"
        if ip link delete "$BRIDGE_IF" >/dev/null 2>&1; then
            log "DEBUG" "Bridge interface $BRIDGE_IF removed successfully"
        else
            log "WARN" "Failed to remove bridge interface $BRIDGE_IF"
        fi
    else
        log "DEBUG" "Bridge interface $BRIDGE_IF does not exist"
    fi
    
    log "INFO" "Network interface cleanup completed"
}

# Clean up any remaining Docker networks
cleanup_docker_networks() {
    log "INFO" "Cleaning up Docker networks..."
    
    # List custom networks (excluding default ones)
    local custom_networks=$(docker network ls --format "{{.Name}}" --filter "type=custom" 2>/dev/null || true)
    
    if [[ -n "$custom_networks" ]]; then
        log "DEBUG" "Found custom networks: $custom_networks"
        for network in $custom_networks; do
            # Skip default networks
            if [[ "$network" != "bridge" && "$network" != "host" && "$network" != "none" ]]; then
                log "DEBUG" "Removing custom network: $network"
                if docker network rm "$network" >/dev/null 2>&1; then
                    log "DEBUG" "Network $network removed successfully"
                else
                    log "WARN" "Failed to remove network $network"
                fi
            fi
        done
    else
        log "DEBUG" "No custom networks found"
    fi
    
    log "INFO" "Docker network cleanup completed"
}

# Clean up any remaining Docker volumes
cleanup_docker_volumes() {
    log "INFO" "Cleaning up Docker volumes..."
    
    # List dangling volumes
    local dangling_volumes=$(docker volume ls -q -f dangling=true 2>/dev/null || true)
    
    if [[ -n "$dangling_volumes" ]]; then
        log "DEBUG" "Found dangling volumes: $dangling_volumes"
        for volume in $dangling_volumes; do
            log "DEBUG" "Removing dangling volume: $volume"
            if docker volume rm "$volume" >/dev/null 2>&1; then
                log "DEBUG" "Volume $volume removed successfully"
            else
                log "WARN" "Failed to remove volume $volume"
            fi
        done
    else
        log "DEBUG" "No dangling volumes found"
    fi
    
    log "INFO" "Docker volume cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "INFO" "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if containers still exist
    for container in "$AWS_CONTAINER" "$GCP_CONTAINER"; do
        if docker ps -a -q -f name="^${container}$" >/dev/null 2>&1; then
            log "WARN" "Container $container still exists"
            ((cleanup_issues++))
        fi
    done
    
    # Check if network interfaces still exist
    for iface in "$AWS_BR_IF" "$GCP_BR_IF" "$BRIDGE_IF"; do
        if ip link show "$iface" >/dev/null 2>&1; then
            log "WARN" "Network interface $iface still exists"
            ((cleanup_issues++))
        fi
    done
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "INFO" "Cleanup verification: SUCCESS - All resources removed"
    else
        log "WARN" "Cleanup verification: WARNING - $cleanup_issues resources still exist"
    fi
}

# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================

main() {
    log "INFO" "Starting VPP test environment cleanup"
    log "INFO" "Log file: $LOG_FILE"
    
    # Check OS compatibility first
    check_os
    
    # Check system requirements
    check_requirements
    
    # Display cleanup plan
    log "INFO" "Cleanup plan:"
    log "INFO" "  1. Stop and remove Docker containers"
    log "INFO" "  2. Remove host network interfaces"
    log "INFO" "  3. Clean up Docker networks and volumes"
    log "INFO" "  4. Verify cleanup completion"
    
    # Step 1: Clean up Docker containers
    cleanup_docker_containers
    
    # Step 2: Clean up network interfaces
    cleanup_network_interfaces
    
    # Step 3: Clean up Docker networks and volumes
    cleanup_docker_networks
    cleanup_docker_volumes
    
    # Step 4: Verify cleanup completion
    verify_cleanup
    
    log "INFO" "VPP test environment cleanup completed"
    echo "Cleanup complete!"
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi