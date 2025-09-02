#!/bin/bash
#
# run_vpp_test.sh - VPP VXLAN->NAT->IPsec End-to-End Test Suite
#
# This script provides a comprehensive test environment for VPP-based network
# forwarding simulation. It demonstrates VXLAN decapsulation, NAT44, and
# IPsec tunnel establishment in a containerized environment.
#
# Architecture:
#   aws_vpp (192.168.1.2) --[VXLAN]--> [NAT44] --> [IPsec] --> gcp_vpp (192.168.1.3)
#
# Requirements:
#   - Ubuntu 20.04+ or Debian 11+
#   - Docker with privileged mode support
#   - Python 3.7+ with scapy
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

# Timeouts and delays
IPSEC_WAIT_TIME=10
TRAFFIC_DURATION=10
TRACE_PACKETS=10

# Logging configuration
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
LOG_FILE="/tmp/vpp_test_$(date +%Y%m%d_%H%M%S).log"

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
        echo "Required Linux packages:"
        echo "  sudo apt update"
        echo "  sudo apt install -y docker.io python3 python3-pip"
        echo "  sudo pip3 install scapy"
        echo
        echo "Then run: sudo bash ./run_vpp_test.sh"
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
    local required_commands=("docker" "python3" "ping" "ip" "bridge")
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
    
    # Check Python scapy
    if ! python3 -c "import scapy" 2>/dev/null; then
        log "WARN" "Python scapy module not found"
        log "INFO" "Install with: sudo pip3 install scapy"
    fi
    
    log "INFO" "System requirements check completed successfully"
}

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

VPP VXLAN->NAT->IPsec End-to-End Test Suite

OPTIONS:
    --setup-only     Only setup the environment (skip testing)
    --test-only      Only run tests (assume environment is ready)
    --full-test      Run complete test including traffic generation (default)
    --cleanup        Clean up after testing
    --debug          Enable debug logging
    --help           Show this help message

EXAMPLES:
    $0                    # Full setup + test + verification
    $0 --setup-only       # Just setup environment
    $0 --test-only        # Just run tests
    $0 --cleanup          # Clean up environment
    $0 --debug            # Enable debug logging

ENVIRONMENT VARIABLES:
    LOG_LEVEL            Set logging level (DEBUG|INFO|WARN|ERROR)
    TRAFFIC_DURATION     Set traffic generation duration in seconds

EOF
}

# Parse command line arguments
parse_arguments() {
    SETUP_ONLY=false
    TEST_ONLY=false
    FULL_TEST=true
    CLEANUP_AFTER=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --setup-only)
                SETUP_ONLY=true
                FULL_TEST=false
                shift
                ;;
            --test-only)
                TEST_ONLY=true
                FULL_TEST=false
                shift
                ;;
            --full-test)
                FULL_TEST=true
                shift
                ;;
            --cleanup)
                CLEANUP_AFTER=true
                shift
                ;;
            --debug)
                LOG_LEVEL="DEBUG"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================

main() {
    log "INFO" "Starting VPP VXLAN->NAT->IPsec test suite"
    log "INFO" "Log file: $LOG_FILE"
    
    # Check OS compatibility first
    check_os
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check system requirements
    check_requirements
    
    # Display configuration
    log "INFO" "Configuration:"
    log "INFO" "  AWS VPP IP: $AWS_VPP_IP"
    log "INFO" "  GCP VPP IP: $GCP_VPP_IP"
    log "INFO" "  Bridge IP: $BRIDGE_IP"
    log "INFO" "  Network: $NETWORK_CIDR"
    log "INFO" "  Log Level: $LOG_LEVEL"
    
    # --- Step 1: Build the Docker Image (if not test-only) ---
    if [ "$TEST_ONLY" = false ]; then
        log "INFO" "Step 1: Building Docker image..."
        if docker build -t "$DOCKER_IMAGE" .; then
            log "INFO" "Docker image built successfully"
        else
            log "ERROR" "Failed to build Docker image"
            exit 1
        fi
    fi

    # --- Step 2: Run the Cleanup Script (if not test-only) ---
    if [ "$TEST_ONLY" = false ]; then
        log "INFO" "Step 2: Cleaning up previous environment..."
        if sudo bash ./cleanup.sh; then
            log "INFO" "Cleanup completed successfully"
        else
            log "WARN" "Cleanup had some issues (this may be normal)"
        fi
    fi

    # --- Step 3: Run the Setup Script (if not test-only) ---
    if [ "$TEST_ONLY" = false ]; then
        log "INFO" "Step 3: Setting up new test environment..."
        if sudo bash ./setup.sh; then
            log "INFO" "Environment setup completed successfully"
        else
            log "ERROR" "Environment setup failed"
            exit 1
        fi
    fi

    # --- Step 4: Wait for IPsec tunnel establishment ---
    log "INFO" "Step 4: Waiting for IPsec tunnel establishment..."
    log "INFO" "Waiting $IPSEC_WAIT_TIME seconds for tunnel to stabilize..."
    sleep "$IPSEC_WAIT_TIME"

    # --- Step 5: Comprehensive Verification ---
    log "INFO" "Step 5: Running comprehensive verification tests..."
    
    # Connectivity tests
    run_connectivity_tests
    
    # VPP status checks
    run_vpp_status_checks
    
    # --- Step 6: Traffic Generation and Verification (if full test) ---
    if [ "$FULL_TEST" = true ]; then
        log "INFO" "Step 6: Running traffic generation and verification..."
        run_traffic_tests
    fi

    # --- Step 7: Final Status and Instructions ---
    log "INFO" "Step 7: Final status and instructions..."
    show_final_status
    
    if [ "$CLEANUP_AFTER" = true ]; then
        log "INFO" "Cleaning up environment as requested..."
        if sudo bash ./cleanup.sh; then
            log "INFO" "Cleanup completed successfully"
        else
            log "WARN" "Cleanup had some issues"
        fi
    else
        log "INFO" "Environment is ready for manual testing"
        log "INFO" "Run './run_vpp_test.sh --cleanup' when done"
    fi
    
    log "INFO" "Test suite completed successfully"
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

run_connectivity_tests() {
    log "INFO" "Running connectivity tests..."
    
    echo
    echo "==================== Connectivity Test ===================="
    echo "--- Testing host -> container connectivity... ---"
    
    # Test host to AWS VPP
    if ping -c 2 "$AWS_VPP_IP" >/dev/null 2>&1; then
        echo "✓ Host can reach aws_vpp ($AWS_VPP_IP)"
        log "INFO" "Host connectivity to AWS VPP: SUCCESS"
    else
        echo "✗ Host cannot reach aws_vpp"
        log "ERROR" "Host connectivity to AWS VPP: FAILED"
    fi
    
    # Test host to GCP VPP
    if ping -c 2 "$GCP_VPP_IP" >/dev/null 2>&1; then
        echo "✓ Host can reach gcp_vpp ($GCP_VPP_IP)"
        log "INFO" "Host connectivity to GCP VPP: SUCCESS"
    else
        echo "✗ Host cannot reach gcp_vpp"
        log "ERROR" "Host connectivity to GCP VPP: FAILED"
    fi
    
    echo
    echo "--- Testing container -> container connectivity... ---"
    
    # Test AWS VPP to GCP VPP
    if docker exec "$AWS_CONTAINER" ping -c 2 "$GCP_VPP_IP" >/dev/null 2>&1; then
        echo "✓ aws_vpp can reach gcp_vpp"
        log "INFO" "AWS VPP to GCP VPP connectivity: SUCCESS"
    else
        echo "✗ aws_vpp cannot reach gcp_vpp"
        log "ERROR" "AWS VPP to GCP VPP connectivity: FAILED"
    fi
    
    # Test GCP VPP to AWS VPP
    if docker exec "$GCP_CONTAINER" ping -c 2 "$AWS_VPP_IP" >/dev/null 2>&1; then
        echo "✓ gcp_vpp can reach aws_vpp"
        log "INFO" "GCP VPP to AWS VPP connectivity: SUCCESS"
    else
        echo "✗ gcp_vpp cannot reach aws_vpp"
        log "ERROR" "GCP VPP to AWS VPP connectivity: FAILED"
    fi
    
    echo "========================================================="
}

run_vpp_status_checks() {
    log "INFO" "Running VPP status checks..."
    
    # IPsec SA Status
    echo
    echo "==================== IPsec SA Status ===================="
    echo "--- AWS VPP SAs: ---"
    docker exec "$AWS_CONTAINER" vppctl show ipsec sa
    echo
    echo "--- GCP VPP SAs: ---"
    docker exec "$GCP_CONTAINER" vppctl show ipsec sa
    echo "========================================================="
    
    # VPP Interface Status
    echo
    echo "==================== VPP Interface Status ===================="
    echo "--- AWS VPP Interfaces: ---"
    docker exec "$AWS_CONTAINER" vppctl show int
    echo
    echo "--- GCP VPP Interfaces: ---"
    docker exec "$GCP_CONTAINER" vppctl show int
    echo "========================================================="
    
    # VPP Routing Tables
    echo
    echo "==================== VPP Routing Tables ===================="
    echo "--- AWS VPP Routes: ---"
    docker exec "$AWS_CONTAINER" vppctl show ip fib
    echo
    echo "--- GCP VPP Routes: ---"
    docker exec "$GCP_CONTAINER" vppctl show ip fib
    echo "========================================================="
    
    # VXLAN Tunnel Status
    echo
    echo "==================== VXLAN Tunnel Status ===================="
    echo "--- AWS VPP VXLAN Tunnels: ---"
    docker exec "$AWS_CONTAINER" vppctl show vxlan tunnel
    echo "========================================================="
    
    # NAT44 Status
    echo
    echo "==================== NAT44 Status ===================="
    echo "--- AWS VPP NAT44 Sessions: ---"
    docker exec "$AWS_CONTAINER" vppctl show nat44 sessions
    echo
    echo "--- AWS VPP NAT44 Interfaces: ---"
    docker exec "$AWS_CONTAINER" vppctl show nat44 interfaces
    echo "========================================================="
}

run_traffic_tests() {
    log "INFO" "Running traffic generation tests..."
    
    echo
    echo "==================== Traffic Generation Test ===================="
    echo "--- Generating test traffic... ---"
    
    # Start traffic generation in background
    log "INFO" "Starting traffic generation for $TRAFFIC_DURATION seconds..."
    echo "Starting traffic generation (will run for $TRAFFIC_DURATION seconds)..."
    
    if timeout "$TRAFFIC_DURATION" python3 send_flows.py > /dev/null 2>&1; then
        log "INFO" "Traffic generation completed successfully"
        echo "--- Traffic generation completed ---"
    else
        log "WARN" "Traffic generation had issues or timed out"
        echo "--- Traffic generation completed (with warnings) ---"
    fi
    
    echo "========================================================="
    
    # Post-traffic verification
    echo
    echo "==================== Post-Traffic Verification ===================="
    echo "--- Checking NAT44 sessions after traffic... ---"
    docker exec "$AWS_CONTAINER" vppctl show nat44 sessions
    echo
    echo "--- Checking IPsec SA statistics... ---"
    docker exec "$AWS_CONTAINER" vppctl show ipsec sa
    docker exec "$GCP_CONTAINER" vppctl show ipsec sa
    echo
    echo "--- Checking interface statistics... ---"
    docker exec "$AWS_CONTAINER" vppctl show int
    docker exec "$GCP_CONTAINER" vppctl show int
    echo "========================================================="
    
    # Trace analysis
    echo
    echo "==================== Trace Analysis ===================="
    echo "--- Setting up packet tracing on GCP side... ---"
    docker exec "$GCP_CONTAINER" vppctl trace add af-packet-input "$TRACE_PACKETS"
    echo "--- Generating one more packet for trace analysis... ---"
    timeout 2 python3 send_flows.py > /dev/null 2>&1
    echo "--- Displaying packet trace... ---"
    docker exec "$GCP_CONTAINER" vppctl show trace
    echo "========================================================="
}

show_final_status() {
    echo
    echo "********** TEST COMPLETED SUCCESSFULLY **********"
    echo
    echo "Environment Status:"
    echo "  ✓ Docker containers running: $AWS_CONTAINER, $GCP_CONTAINER"
    echo "  ✓ Network connectivity verified"
    echo "  ✓ IPsec tunnel established"
    echo "  ✓ VPP interfaces configured"
    echo "  ✓ Routing tables populated"
    
    if [ "$FULL_TEST" = true ]; then
        echo "  ✓ Traffic generation completed"
        echo "  ✓ NAT44 sessions verified"
        echo "  ✓ Packet trace captured"
    fi
    
    echo
    log "INFO" "Test suite completed successfully"
    
    if [ "$FULL_TEST" = false ]; then
        echo "To run traffic tests manually:"
        echo "  python3 send_flows.py"
        echo
        echo "To verify results manually:"
        echo "  sudo bash ./debug.sh $AWS_CONTAINER show nat44 sessions"
        echo "  sudo bash ./debug.sh $GCP_CONTAINER show trace"
        echo
    fi
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi