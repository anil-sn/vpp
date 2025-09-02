#!/bin/bash
#
# setup_huge.sh - HugePages Setup Script for DPDK/VPP
#
# This script sets up HugePages for optimal DPDK and VPP performance.
# HugePages provide larger memory pages that improve performance for
# high-throughput networking applications by reducing TLB misses.
#
# Features:
#   - Automatic HugePages allocation
#   - NUMA-aware configuration
#   - Mount point setup
#   - Performance optimization
#   - Comprehensive error handling
#
# Requirements:
#   - Ubuntu 20.04+ or Debian 11+
#   - Root/sudo access
#   - x86_64 architecture (for 2MB pages)
#   - Sufficient memory for HugePages allocation
#
# Author: Network Engineering Team
# Version: 2.0
# Last Updated: 2024

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

# HugePages configuration
HUGE_PAGE_SIZE="2048kB"  # 2MB pages (standard for x86_64)
HUGE_PAGES_COUNT=1024    # Number of HugePages to allocate
NUMA_NODE=0              # NUMA node to allocate pages on
MOUNT_POINT="/mnt/huge"  # Mount point for HugePages filesystem

# System limits
MAX_HUGE_PAGES=65536     # Maximum HugePages allowed by kernel
MIN_MEMORY_GB=4          # Minimum system memory required in GB

# Timeouts and delays
SETUP_TIMEOUT=30         # Timeout for setup operations in seconds

# Logging configuration
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
LOG_FILE="/tmp/hugepages_setup_$(date +%Y%m%d_%H%M%S).log"

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
        echo "You are running on macOS, which doesn't support HugePages or DPDK."
        echo "This script is designed for Linux systems that support DPDK."
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
    
    # Check architecture
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        log "WARN" "Architecture $arch detected. HugePages setup may not be optimal."
        log "INFO" "This script is optimized for x86_64 architecture"
    fi
    
    # Check available memory
    local total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_memory_gb=$((total_memory_kb / 1024 / 1024))
    
    log "INFO" "System memory: ${total_memory_gb}GB"
    
    if [[ $total_memory_gb -lt $MIN_MEMORY_GB ]]; then
        log "ERROR" "Insufficient system memory: ${total_memory_gb}GB (minimum: ${MIN_MEMORY_GB}GB)"
        exit 1
    fi
    
    # Check if HugePages are supported
    if [[ ! -d "/sys/devices/system/node/node${NUMA_NODE}/hugepages/hugepages-${HUGE_PAGE_SIZE}" ]]; then
        log "ERROR" "HugePages not supported on NUMA node $NUMA_NODE"
        log "INFO" "Available NUMA nodes:"
        ls -d /sys/devices/system/node/node* 2>/dev/null | sed 's/.*node//' || echo "None found"
        exit 1
    fi
    
    log "INFO" "System requirements check completed successfully"
}

# Calculate optimal HugePages count
calculate_hugepages_count() {
    log "INFO" "Calculating optimal HugePages count..."
    
    local total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_memory_gb=$((total_memory_kb / 1024 / 1024))
    
    # Reserve 25% of memory for system, allocate 75% to HugePages
    local available_memory_gb=$((total_memory_gb * 75 / 100))
    local hugepages_gb=$((available_memory_gb * 1024 / 2048))  # Convert to 2MB pages
    
    # Limit to reasonable maximum
    if [[ $hugepages_gb -gt $MAX_HUGE_PAGES ]]; then
        hugepages_gb=$MAX_HUGE_PAGES
        log "WARN" "Limiting HugePages to maximum allowed: $MAX_HUGE_PAGES"
    fi
    
    # Ensure minimum allocation
    if [[ $hugepages_gb -lt $HUGE_PAGES_COUNT ]]; then
        hugepages_gb=$HUGE_PAGES_COUNT
        log "WARN" "Using minimum HugePages allocation: $HUGE_PAGES_COUNT"
    fi
    
    HUGE_PAGES_COUNT=$hugepages_gb
    log "INFO" "Calculated optimal HugePages count: $HUGE_PAGES_COUNT"
    log "INFO" "This will allocate approximately $((hugepages_gb * 2))MB of memory"
}

# Check current HugePages status
check_current_hugepages() {
    log "INFO" "Checking current HugePages status..."
    
    local current_pages=$(cat "/sys/devices/system/node/node${NUMA_NODE}/hugepages/hugepages-${HUGE_PAGE_SIZE}/nr_hugepages" 2>/dev/null || echo "0")
    local free_pages=$(cat "/sys/devices/system/node/node${NUMA_NODE}/hugepages/hugepages-${HUGE_PAGE_SIZE}/free_hugepages" 2>/dev/null || echo "0")
    
    log "INFO" "Current HugePages on NUMA node $NUMA_NODE:"
    log "INFO" "  Total allocated: $current_pages"
    log "INFO" "  Free: $free_pages"
    log "INFO" "  Used: $((current_pages - free_pages))"
    
    if [[ $current_pages -gt 0 ]]; then
        log "WARN" "HugePages already allocated. Consider cleanup before reallocation."
    fi
}

# Allocate HugePages
allocate_hugepages() {
    log "INFO" "Allocating HugePages..."
    
    local hugepages_file="/sys/devices/system/node/node${NUMA_NODE}/hugepages/hugepages-${HUGE_PAGE_SIZE}/nr_hugepages"
    
    log "DEBUG" "Setting HugePages count to $HUGE_PAGES_COUNT on NUMA node $NUMA_NODE"
    
    if echo "$HUGE_PAGES_COUNT" > "$hugepages_file" 2>/dev/null; then
        log "INFO" "HugePages allocation request submitted successfully"
    else
        log "ERROR" "Failed to allocate HugePages"
        exit 1
    fi
    
    # Verify allocation
    local timeout_counter=0
    local allocated_pages=0
    
    while [[ $timeout_counter -lt $SETUP_TIMEOUT ]]; do
        allocated_pages=$(cat "$hugepages_file" 2>/dev/null || echo "0")
        if [[ $allocated_pages -eq $HUGE_PAGES_COUNT ]]; then
            log "INFO" "HugePages allocation verified: $allocated_pages pages"
            break
        fi
        sleep 1
        ((timeout_counter++))
    done
    
    if [[ $allocated_pages -ne $HUGE_PAGES_COUNT ]]; then
        log "ERROR" "HugePages allocation verification failed"
        log "ERROR" "Expected: $HUGE_PAGES_COUNT, Got: $allocated_pages"
        exit 1
    fi
}

# Setup HugePages mount point
setup_mount_point() {
    log "INFO" "Setting up HugePages mount point..."
    
    # Create mount point directory
    if [[ ! -d "$MOUNT_POINT" ]]; then
        log "DEBUG" "Creating mount point directory: $MOUNT_POINT"
        if ! mkdir -p "$MOUNT_POINT"; then
            log "ERROR" "Failed to create mount point directory"
            exit 1
        fi
    fi
    
    # Check if already mounted
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log "WARN" "HugePages filesystem already mounted at $MOUNT_POINT"
        log "INFO" "Unmounting existing filesystem..."
        if ! umount "$MOUNT_POINT"; then
            log "ERROR" "Failed to unmount existing filesystem"
            exit 1
        fi
    fi
    
    # Mount HugePages filesystem
    log "DEBUG" "Mounting HugePages filesystem at $MOUNT_POINT"
    if ! mount -t hugetlbfs nodev "$MOUNT_POINT"; then
        log "ERROR" "Failed to mount HugePages filesystem"
        exit 1
    fi
    
    log "INFO" "HugePages filesystem mounted successfully at $MOUNT_POINT"
}

# Configure system for optimal HugePages performance
configure_system() {
    log "INFO" "Configuring system for optimal HugePages performance..."
    
    # Set vm.nr_hugepages kernel parameter
    local hugepages_kb=$((HUGE_PAGES_COUNT * 2048))
    local hugepages_mb=$((hugepages_kb / 1024))
    
    log "DEBUG" "Setting kernel parameter vm.nr_hugepages to $HUGE_PAGES_COUNT"
    if ! sysctl -w "vm.nr_hugepages=$HUGE_PAGES_COUNT" >/dev/null 2>&1; then
        log "WARN" "Failed to set vm.nr_hugepages kernel parameter"
    fi
    
    # Set vm.hugetlb_shm_group for shared memory access
    log "DEBUG" "Setting kernel parameter vm.hugetlb_shm_group to 0 (root group)"
    if ! sysctl -w "vm.hugetlb_shm_group=0" >/dev/null 2>&1; then
        log "WARN" "Failed to set vm.hugetlb_shm_group kernel parameter"
    fi
    
    # Set vm.max_map_count for large memory mappings
    local max_map_count=$((HUGE_PAGES_COUNT * 4))  # 4x HugePages count
    log "DEBUG" "Setting kernel parameter vm.max_map_count to $max_map_count"
    if ! sysctl -w "vm.max_map_count=$max_map_count" >/dev/null 2>&1; then
        log "WARN" "Failed to set vm.max_map_count kernel parameter"
    fi
    
    log "INFO" "System configuration completed"
}

# Verify HugePages setup
verify_setup() {
    log "INFO" "Verifying HugePages setup..."
    
    local verification_passed=true
    
    # Check HugePages allocation
    local allocated_pages=$(cat "/sys/devices/system/node/node${NUMA_NODE}/hugepages/hugepages-${HUGE_PAGE_SIZE}/nr_hugepages" 2>/dev/null || echo "0")
    if [[ $allocated_pages -ne $HUGE_PAGES_COUNT ]]; then
        log "ERROR" "HugePages allocation verification failed"
        verification_passed=false
    fi
    
    # Check mount point
    if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log "ERROR" "HugePages filesystem not mounted"
        verification_passed=false
    fi
    
    # Check filesystem type
    local mount_type=$(findmnt -n -o FSTYPE "$MOUNT_POINT" 2>/dev/null || echo "")
    if [[ "$mount_type" != "hugetlbfs" ]]; then
        log "ERROR" "Incorrect filesystem type: $mount_type (expected: hugetlbfs)"
        verification_passed=false
    fi
    
    # Check permissions
    if [[ ! -r "$MOUNT_POINT" || ! -w "$MOUNT_POINT" ]]; then
        log "ERROR" "Insufficient permissions on mount point"
        verification_passed=false
    fi
    
    if [[ "$verification_passed" == "true" ]]; then
        log "INFO" "HugePages setup verification: SUCCESS"
        echo "✓ HugePages setup completed successfully"
        echo "  - Allocated: $allocated_pages pages (${HUGE_PAGE_SIZE})"
        echo "  - Mount point: $MOUNT_POINT"
        echo "  - NUMA node: $NUMA_NODE"
        echo "  - Memory usage: $((allocated_pages * 2))MB"
    else
        log "ERROR" "HugePages setup verification: FAILED"
        echo "✗ HugePages setup verification failed"
        exit 1
    fi
}

# Show HugePages status
show_hugepages_status() {
    log "INFO" "Displaying HugePages status..."
    
    echo
    echo "==================== HugePages Status ===================="
    
    # System-wide HugePages info
    echo "--- System HugePages Information ---"
    if [[ -f "/proc/meminfo" ]]; then
        grep -i huge /proc/meminfo | while read line; do
            echo "  $line"
        done
    fi
    
    # NUMA-specific HugePages info
    echo -e "\n--- NUMA Node $NUMA_NODE HugePages Information ---"
    local hugepages_dir="/sys/devices/system/node/node${NUMA_NODE}/hugepages"
    if [[ -d "$hugepages_dir" ]]; then
        for page_size_dir in "$hugepages_dir"/hugepages-*; do
            if [[ -d "$page_size_dir" ]]; then
                local page_size=$(basename "$page_size_dir" | sed 's/hugepages-//')
                local nr_hugepages=$(cat "$page_size_dir/nr_hugepages" 2>/dev/null || echo "0")
                local free_hugepages=$(cat "$page_size_dir/free_hugepages" 2>/dev/null || echo "0")
                local surplus_hugepages=$(cat "$page_size_dir/surplus_hugepages" 2>/dev/null || echo "0")
                
                echo "  Page Size: $page_size"
                echo "    Total: $nr_hugepages"
                echo "    Free: $free_hugepages"
                echo "    Surplus: $surplus_hugepages"
            fi
        done
    fi
    
    # Mount point information
    echo -e "\n--- Mount Point Information ---"
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        findmnt "$MOUNT_POINT" | while read line; do
            echo "  $line"
        done
    else
        echo "  Not mounted"
    fi
    
    echo "========================================================="
}

# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================

main() {
    log "INFO" "Starting HugePages setup for DPDK/VPP optimization"
    log "INFO" "Log file: $LOG_FILE"
    
    # Check OS compatibility first
    check_os
    
    # Check system requirements
    check_requirements
    
    # Display configuration
    log "INFO" "Configuration:"
    log "INFO" "  HugePage Size: $HUGE_PAGE_SIZE"
    log "INFO" "  HugePages Count: $HUGE_PAGES_COUNT"
    log "INFO" "  NUMA Node: $NUMA_NODE"
    log "INFO" "  Mount Point: $MOUNT_POINT"
    log "INFO" "  Log Level: $LOG_LEVEL"
    
    # Step 1: Calculate optimal HugePages count
    calculate_hugepages_count
    
    # Step 2: Check current HugePages status
    check_current_hugepages
    
    # Step 3: Allocate HugePages
    allocate_hugepages
    
    # Step 4: Setup mount point
    setup_mount_point
    
    # Step 5: Configure system
    configure_system
    
    # Step 6: Verify setup
    verify_setup
    
    # Step 7: Show status
    show_hugepages_status
    
    log "INFO" "HugePages setup completed successfully"
    echo
    echo "HugePages setup complete for NUMA node $NUMA_NODE."
    echo "The system is now optimized for DPDK and VPP performance."
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
