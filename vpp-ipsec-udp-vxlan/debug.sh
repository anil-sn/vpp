#!/bin/bash
#
# debug.sh - VPP Debugging and Inspection Tool
#
# This script is a flexible debugging tool to run any vppctl command inside
# one of the running containers. It simplifies the process of inspecting
# the VPP state and provides enhanced error handling and logging.
#
# Features:
#   - Container validation
#   - Command execution with error handling
#   - Enhanced logging and output formatting
#   - Common VPP command shortcuts
#   - Container health checks
#
# Requirements:
#   - Ubuntu 20.04+ or Debian 11+
#   - Docker with privileged mode support
#   - Running VPP containers
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

# VPP socket path
VPP_CLI_SOCKET="/run/vpp/cli.sock"

# Timeouts and delays
CONTAINER_CHECK_TIMEOUT=5
VPP_READY_TIMEOUT=10

# Logging configuration
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
LOG_FILE="/tmp/vpp_debug_$(date +%Y%m%d_%H%M%S).log"

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
        echo "  - Docker container management"
        echo "  - VPP socket access"
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
    
    # Check for required commands
    local required_commands=("docker")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "Required command '$cmd' not found"
            log "INFO" "Install with: sudo apt install -y docker.io"
            exit 1
        fi
    done
    
    # Check Docker service
    if ! systemctl is-active --quiet docker; then
        log "ERROR" "Docker service is not running"
        log "INFO" "Start with: sudo systemctl start docker"
        exit 1
    fi
    
    log "INFO" "System requirements check completed successfully"
}

# Validate container name
validate_container() {
    local container="$1"
    
    # Check if container name is valid
    case "$container" in
        "$AWS_CONTAINER"|"$GCP_CONTAINER")
            log "DEBUG" "Container name validated: $container"
            return 0
            ;;
        *)
            log "ERROR" "Invalid container name: $container"
            log "INFO" "Valid containers: $AWS_CONTAINER, $GCP_CONTAINER"
            return 1
            ;;
    esac
}

# Check if container is running
check_container_running() {
    local container="$1"
    
    log "DEBUG" "Checking if container $container is running..."
    
    if ! docker ps -q -f name="^${container}$" >/dev/null 2>&1; then
        log "ERROR" "Container $container is not running"
        log "INFO" "Available containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
        return 1
    fi
    
    log "DEBUG" "Container $container is running"
    return 0
}

# Check if VPP is ready in container
check_vpp_ready() {
    local container="$1"
    
    log "DEBUG" "Checking if VPP is ready in container $container..."
    
    local timeout_counter=0
    while [[ $timeout_counter -lt $VPP_READY_TIMEOUT ]]; do
        if docker exec "$container" test -S "$VPP_CLI_SOCKET" 2>/dev/null; then
            log "DEBUG" "VPP is ready in container $container"
            return 0
        fi
        sleep 1
        ((timeout_counter++))
    done
    
    log "ERROR" "Timeout waiting for VPP to be ready in container $container"
    return 1
}

# Execute vppctl command with error handling
execute_vppctl_command() {
    local container="$1"
    shift
    local command="$*"
    
    log "INFO" "Executing 'vppctl $command' in container '$container'"
    
    # Validate container
    if ! validate_container "$container"; then
        return 1
    fi
    
    # Check if container is running
    if ! check_container_running "$container"; then
        return 1
    fi
    
    # Check if VPP is ready
    if ! check_vpp_ready "$container"; then
        return 1
    fi
    
    # Execute the command
    log "DEBUG" "Running: docker exec $container vppctl $command"
    
    if docker exec "$container" vppctl "$@"; then
        log "INFO" "Command executed successfully"
        return 0
    else
        log "ERROR" "Command execution failed"
        return 1
    fi
}

# Show container health status
show_container_health() {
    local container="$1"
    
    log "INFO" "Container health status for $container:"
    
    # Container status
    echo "=== Container Status ==="
    docker ps --filter "name=^${container}$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}"
    
    # VPP process status
    echo -e "\n=== VPP Process Status ==="
    if docker exec "$container" pgrep -f vpp >/dev/null 2>&1; then
        echo "✓ VPP process is running"
        docker exec "$container" ps aux | grep vpp | grep -v grep || echo "No VPP process details available"
    else
        echo "✗ VPP process is not running"
    fi
    
    # VPP socket status
    echo -e "\n=== VPP Socket Status ==="
    if docker exec "$container" test -S "$VPP_CLI_SOCKET" 2>/dev/null; then
        echo "✓ VPP CLI socket is available"
        docker exec "$container" ls -la "$VPP_CLI_SOCKET" 2>/dev/null || echo "Cannot access socket details"
    else
        echo "✗ VPP CLI socket is not available"
    fi
    
    # Container resource usage
    echo -e "\n=== Resource Usage ==="
    docker stats "$container" --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || echo "Cannot retrieve resource stats"
}

# Show common VPP commands help
show_vpp_help() {
    cat << EOF
Common VPP Commands for Debugging:

=== Interface Commands ===
  show int                    # Show all interfaces
  show int addr              # Show interface addresses
  show int features          # Show interface features
  show int rx-placement      # Show RX placement

=== IPsec Commands ===
  show ipsec sa              # Show IPsec Security Associations
  show ipsec sa detail       # Show detailed SA information
  show ipsec tunnel          # Show IPsec tunnels
  show ipsec tunnel detail   # Show detailed tunnel information

=== NAT Commands ===
  show nat44 sessions        # Show NAT44 sessions
  show nat44 interfaces      # Show NAT44 interface bindings
  show nat44 timeouts        # Show NAT44 timeouts

=== VXLAN Commands ===
  show vxlan tunnel          # Show VXLAN tunnels
  show vxlan tunnel detail   # Show detailed VXLAN information

=== Routing Commands ===
  show ip fib                # Show IP forwarding table
  show ip fib summary        # Show FIB summary
  show ip route              # Show IP routes

=== Trace Commands ===
  trace add af-packet-input 10    # Add trace for 10 packets
  show trace                       # Show packet trace
  clear trace                      # Clear trace buffer

=== Statistics Commands ===
  show error                    # Show error counters
  show runtime                  # Show runtime statistics
  clear error                   # Clear error counters

=== Debug Commands ===
  set logging class ipsec level debug    # Enable IPsec debug logging
  set logging class nat level debug      # Enable NAT debug logging
  show logging                           # Show logging configuration

Examples:
  $0 $AWS_CONTAINER show int
  $0 $GCP_CONTAINER show ipsec sa
  $0 $AWS_CONTAINER trace add af-packet-input 5
  $0 $GCP_CONTAINER show trace

EOF
}

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 <container_name> <vppctl_command_with_args>

VPP Debugging and Inspection Tool

ARGUMENTS:
    container_name           Name of the container (aws_vpp or gcp_vpp)
    vppctl_command_with_args VPP command and arguments to execute

OPTIONS:
    --health <container>    Show container health status
    --help                  Show this help message
    --debug                 Enable debug logging

EXAMPLES:
    $0 aws_vpp show nat44 sessions
    $0 gcp_vpp show ipsec sa
    $0 aws_vpp show vxlan tunnel
    $0 gcp_vpp show int
    $0 aws_vpp trace add af-packet-input 10
    $0 gcp_vpp show trace
    $0 --health aws_vpp
    $0 --help

CONTAINERS:
    $AWS_CONTAINER          AWS VPP instance (192.168.1.2)
    $GCP_CONTAINER          GCP VPP instance (192.168.1.3)

EOF
}

# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================

main() {
    log "INFO" "Starting VPP debugging tool"
    log "INFO" "Log file: $LOG_FILE"
    
    # Check OS compatibility first
    check_os
    
    # Check system requirements
    check_requirements
    
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        log "ERROR" "No arguments provided"
        show_usage
        exit 1
    fi
    
    # Handle special options
    case "$1" in
        --help)
            show_usage
            exit 0
            ;;
        --health)
            if [[ -z "$2" ]]; then
                log "ERROR" "Container name required for --health option"
                show_usage
                exit 1
            fi
            show_container_health "$2"
            exit 0
            ;;
        --debug)
            LOG_LEVEL="DEBUG"
            shift
            ;;
    esac
    
    # Check if we have enough arguments
    if [[ $# -lt 2 ]]; then
        log "ERROR" "Insufficient arguments"
        show_usage
        exit 1
    fi
    
    local container="$1"
    shift
    local command="$*"
    
    # Execute the vppctl command
    if execute_vppctl_command "$container" "$command"; then
        log "INFO" "Command completed successfully"
    else
        log "ERROR" "Command failed"
        exit 1
    fi
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi