#!/bin/bash
# Production Environment Discovery Script
# This script investigates existing infrastructure and prepares deployment parameters

set -e

# Color codes for output
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

# Configuration
DISCOVERY_DIR="${DISCOVERY_DIR:-/tmp/vpp_discovery_$(date +%Y%m%d_%H%M%S)}"
VERBOSE=${VERBOSE:-false}

# Help function
show_help() {
    cat << EOF
VPP Multi-Container Chain - Environment Discovery Tool

Usage: $0 [OPTIONS]

OPTIONS:
  -d, --discovery-dir DIR    Discovery output directory (default: /tmp/vpp_discovery_TIMESTAMP)
  -v, --verbose             Enable verbose output
  -h, --help               Show this help message

DESCRIPTION:
  This script performs comprehensive environment discovery to prepare for VPP
  multi-container chain deployment. It analyzes system resources, network
  configuration, cloud environment, existing applications, and traffic patterns.

EXAMPLES:
  $0                                    # Basic discovery
  $0 -d /opt/vpp_discovery             # Custom discovery directory  
  $0 -v                                # Verbose discovery
  
OUTPUT:
  The script creates a discovery directory containing:
  - discovery_report.txt       # Complete discovery summary
  - system_info.txt           # System resources and specs
  - network_config.txt        # Network interfaces and routing
  - cloud_environment.txt     # Cloud provider detection
  - application_discovery.txt # Existing services analysis
  - traffic_analysis.txt      # Traffic pattern analysis
  
NEXT STEPS:
  After discovery completion:
  1. Review the discovery report
  2. Generate production config: tools/config-generator/production_config_generator.py DISCOVERY_DIR
  3. Deploy: sudo python3 src/main.py setup --config production_generated.json

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--discovery-dir)
            DISCOVERY_DIR="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Verbose logging
verbose_log() {
    if [ "$VERBOSE" = true ]; then
        log_info "$1"
    fi
}

# Create discovery directory
mkdir -p "$DISCOVERY_DIR"
verbose_log "Created discovery directory: $DISCOVERY_DIR"

log_info "=== VPP Multi-Container Chain Environment Discovery ==="
echo "Discovery started at: $(date)" | tee "$DISCOVERY_DIR/discovery_report.txt"
echo "Discovery directory: $DISCOVERY_DIR" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

# 1. System Information Discovery
log_info "1. System Information Discovery"
echo "1. SYSTEM INFORMATION DISCOVERY" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "================================" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

# CPU and Memory Analysis
verbose_log "Analyzing CPU and memory resources..."
echo "CPU Cores: $(nproc)" | tee "$DISCOVERY_DIR/system_info.txt"
echo "Memory: $(free -h | grep '^Mem:' | awk '{print $2}')" | tee -a "$DISCOVERY_DIR/system_info.txt"
echo "System Load: $(uptime | cut -d',' -f3-)" | tee -a "$DISCOVERY_DIR/system_info.txt"
echo "Disk Space: $(df -h / | tail -1 | awk '{print $4}')" | tee -a "$DISCOVERY_DIR/system_info.txt"

# OS and Kernel Information
echo "OS Version: $(lsb_release -d 2>/dev/null | cut -d':' -f2 | sed 's/^[ \t]*//' || cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"')" | tee -a "$DISCOVERY_DIR/system_info.txt"
echo "Kernel Version: $(uname -r)" | tee -a "$DISCOVERY_DIR/system_info.txt"
echo "Architecture: $(uname -m)" | tee -a "$DISCOVERY_DIR/system_info.txt"

cat "$DISCOVERY_DIR/system_info.txt" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

# 2. Network Configuration Discovery
log_info "2. Network Configuration Discovery"
echo "2. NETWORK CONFIGURATION DISCOVERY" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "===================================" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

# Network Interfaces Analysis
verbose_log "Analyzing network interfaces and routing..."
echo "Network Interfaces:" | tee "$DISCOVERY_DIR/network_config.txt"
ip addr show | tee -a "$DISCOVERY_DIR/network_config.txt"

echo "" | tee -a "$DISCOVERY_DIR/network_config.txt"
echo "Routing Table:" | tee -a "$DISCOVERY_DIR/network_config.txt"
ip route show | tee -a "$DISCOVERY_DIR/network_config.txt"

echo "" | tee -a "$DISCOVERY_DIR/network_config.txt"
echo "Active Network Connections:" | tee -a "$DISCOVERY_DIR/network_config.txt"
ss -tuln | head -20 | tee -a "$DISCOVERY_DIR/network_config.txt"

# Extract key network parameters for configuration generation
PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
PRIMARY_IP=$(ip addr show "$PRIMARY_INTERFACE" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
DEFAULT_GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)

echo "" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "Key Network Parameters:" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "  Primary Interface: $PRIMARY_INTERFACE" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "  Primary IP: $PRIMARY_IP" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "  Default Gateway: $DEFAULT_GATEWAY" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

# 3. Cloud Environment Detection
log_info "3. Cloud Environment Detection"
echo "3. CLOUD ENVIRONMENT DETECTION" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "===============================" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

verbose_log "Detecting cloud provider..."

# AWS Detection
if curl -s -m 2 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
    log_success "AWS Environment Detected"
    echo "AWS Environment Detected" | tee "$DISCOVERY_DIR/cloud_environment.txt"
    echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
    echo "Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
    echo "Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
    
    # Try to get VPC information
    MAC=$(curl -s http://169.254.169.254/latest/meta-data/mac)
    VPC_ID=$(curl -s "http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/vpc-id" 2>/dev/null)
    if [ -n "$VPC_ID" ]; then
        echo "VPC ID: $VPC_ID" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
    fi
    
# GCP Detection
elif curl -s -H "Metadata-Flavor: Google" -m 2 http://169.254.169.254/computeMetadata/v1/instance/name >/dev/null 2>&1; then
    log_success "GCP Environment Detected"
    echo "GCP Environment Detected" | tee "$DISCOVERY_DIR/cloud_environment.txt"
    echo "Instance Name: $(curl -s -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/name)" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
    echo "Machine Type: $(curl -s -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/machine-type | cut -d'/' -f4)" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
    echo "Zone: $(curl -s -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/zone | cut -d'/' -f4)" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
    echo "Project ID: $(curl -s -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/project/project-id)" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
    
# Azure Detection
elif curl -s -H "Metadata:true" -m 2 "http://169.254.169.254/metadata/instance?api-version=2021-02-01" >/dev/null 2>&1; then
    log_success "Azure Environment Detected"
    echo "Azure Environment Detected" | tee "$DISCOVERY_DIR/cloud_environment.txt"
    AZURE_METADATA=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01")
    echo "VM Name: $(echo "$AZURE_METADATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['compute']['name'])" 2>/dev/null || echo "N/A")" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
    echo "VM Size: $(echo "$AZURE_METADATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['compute']['vmSize'])" 2>/dev/null || echo "N/A")" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
    echo "Location: $(echo "$AZURE_METADATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['compute']['location'])" 2>/dev/null || echo "N/A")" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
else
    log_info "On-Premises or Private Cloud Environment Detected"
    echo "On-Premises or Private Cloud Environment Detected" | tee "$DISCOVERY_DIR/cloud_environment.txt"
    echo "No public cloud metadata service detected" | tee -a "$DISCOVERY_DIR/cloud_environment.txt"
fi

cat "$DISCOVERY_DIR/cloud_environment.txt" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

# 4. Existing Application Discovery
log_info "4. Existing Application Discovery"
echo "4. EXISTING APPLICATION DISCOVERY" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "==================================" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

verbose_log "Checking for existing VPP and Docker installations..."

# Check for existing VPP installations
echo "VPP Installation Check:" | tee "$DISCOVERY_DIR/application_discovery.txt"
if command -v vpp >/dev/null 2>&1; then
    echo "VPP Version: $(vpp -v 2>/dev/null | head -1 || echo 'VPP found but version not detected')" | tee -a "$DISCOVERY_DIR/application_discovery.txt"
    echo "VPP Status: $(systemctl is-active vpp 2>/dev/null || echo 'not running as systemd service')" | tee -a "$DISCOVERY_DIR/application_discovery.txt"
    log_warning "Existing VPP installation detected"
else
    echo "VPP: not detected" | tee -a "$DISCOVERY_DIR/application_discovery.txt"
    log_success "No existing VPP conflicts detected"
fi

# Check for Docker
echo "" | tee -a "$DISCOVERY_DIR/application_discovery.txt"
echo "Docker Installation Check:" | tee -a "$DISCOVERY_DIR/application_discovery.txt"
if command -v docker >/dev/null 2>&1; then
    echo "Docker Version: $(docker --version)" | tee -a "$DISCOVERY_DIR/application_discovery.txt"
    echo "Docker Status: $(systemctl is-active docker 2>/dev/null || echo 'not running as systemd service')" | tee -a "$DISCOVERY_DIR/application_discovery.txt"
    echo "Running Containers: $(docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null | wc -l) containers" | tee -a "$DISCOVERY_DIR/application_discovery.txt"
    log_success "Docker available for container deployment"
else
    echo "Docker: not detected" | tee -a "$DISCOVERY_DIR/application_discovery.txt"
    log_warning "Docker not available - installation required"
fi

# Check listening services and ports
echo "" | tee -a "$DISCOVERY_DIR/application_discovery.txt"
echo "Listening Services (Top 20):" | tee -a "$DISCOVERY_DIR/application_discovery.txt"
ss -tuln | head -20 | tee -a "$DISCOVERY_DIR/application_discovery.txt"

cat "$DISCOVERY_DIR/application_discovery.txt" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

# 5. Traffic Flow Analysis
log_info "5. Traffic Flow Analysis"
echo "5. TRAFFIC FLOW ANALYSIS" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "=========================" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

verbose_log "Analyzing network traffic patterns..."
echo "Analyzing network traffic patterns..." | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "Traffic Analysis (30-second sample):" | tee "$DISCOVERY_DIR/traffic_analysis.txt"

# Capture traffic statistics
if command -v iftop >/dev/null 2>&1; then
    verbose_log "Using iftop for traffic analysis..."
    timeout 30 iftop -t -s 30 -L 10 2>/dev/null | tee -a "$DISCOVERY_DIR/traffic_analysis.txt" || echo "iftop analysis completed"
elif command -v nethogs >/dev/null 2>&1; then
    verbose_log "Using nethogs for traffic analysis..."
    timeout 30 nethogs -t -d 5 2>/dev/null | head -20 | tee -a "$DISCOVERY_DIR/traffic_analysis.txt" || echo "nethogs analysis completed"
else
    # Basic traffic analysis using /proc/net/dev
    verbose_log "Using basic interface statistics for traffic analysis..."
    cat /proc/net/dev | tee -a "$DISCOVERY_DIR/traffic_analysis.txt"
    echo "Note: Install iftop or nethogs for detailed traffic analysis" | tee -a "$DISCOVERY_DIR/traffic_analysis.txt"
fi

# Network interface statistics
echo "" | tee -a "$DISCOVERY_DIR/traffic_analysis.txt"
echo "Interface Statistics:" | tee -a "$DISCOVERY_DIR/traffic_analysis.txt"
cat /proc/net/dev | tee -a "$DISCOVERY_DIR/traffic_analysis.txt"

cat "$DISCOVERY_DIR/traffic_analysis.txt" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

# Traffic Integration Analysis
log_info "6. Traffic Integration Points"
mkdir -p "$DISCOVERY_DIR/traffic_integration"

# Check for existing VXLAN traffic
echo "VXLAN traffic detection:" | tee "$DISCOVERY_DIR/traffic_integration/vxlan_detection.txt"
if ss -u | grep -q ":4789"; then
    echo "VXLAN traffic detected on port 4789" | tee -a "$DISCOVERY_DIR/traffic_integration/vxlan_detection.txt"
    ss -u | grep ":4789" | tee -a "$DISCOVERY_DIR/traffic_integration/vxlan_detection.txt"
    log_warning "Existing VXLAN traffic detected - integration mode required"
else
    echo "No VXLAN traffic detected on standard port 4789" | tee -a "$DISCOVERY_DIR/traffic_integration/vxlan_detection.txt"
    log_success "No conflicting VXLAN traffic detected"
fi

# Check for flow monitoring traffic (NetFlow, sFlow, IPFIX)
echo "" | tee -a "$DISCOVERY_DIR/traffic_integration/vxlan_detection.txt"
echo "Flow monitoring traffic detection:" | tee -a "$DISCOVERY_DIR/traffic_integration/vxlan_detection.txt"
for port in 2055 6343 4739; do
    if ss -u | grep -q ":$port"; then
        echo "Flow monitoring detected on port $port" | tee -a "$DISCOVERY_DIR/traffic_integration/vxlan_detection.txt"
    fi
done

# Final Discovery Summary
echo "" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "=== DISCOVERY SUMMARY ===" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "Discovery completed at: $(date)" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "Discovery data saved in: $DISCOVERY_DIR" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "Next steps:" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "1. Review discovery report: cat $DISCOVERY_DIR/discovery_report.txt" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "2. Generate production config: tools/config-generator/production_config_generator.py $DISCOVERY_DIR" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "3. Validate configuration: python3 -m json.tool production_generated.json" | tee -a "$DISCOVERY_DIR/discovery_report.txt"
echo "4. Deploy containers: sudo python3 src/main.py setup --config production_generated.json --force" | tee -a "$DISCOVERY_DIR/discovery_report.txt"

echo ""
log_success "=== ENVIRONMENT DISCOVERY COMPLETED ==="
log_info "Discovery report: $DISCOVERY_DIR/discovery_report.txt"
log_info "Next: Generate production.json configuration using:"
echo "       tools/config-generator/production_config_generator.py $DISCOVERY_DIR"

# Set proper permissions
chmod 644 "$DISCOVERY_DIR"/* 2>/dev/null || true
chmod 755 "$DISCOVERY_DIR"
if [ -d "$DISCOVERY_DIR/traffic_integration" ]; then
    chmod 755 "$DISCOVERY_DIR/traffic_integration"
    chmod 644 "$DISCOVERY_DIR/traffic_integration"/* 2>/dev/null || true
fi

log_success "Discovery data saved with proper permissions"