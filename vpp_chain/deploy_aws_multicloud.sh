#!/bin/bash

# AWS Multi-Cloud VPP Chain Deployment Script
# Deploys: VXLAN-PROCESSOR + SECURITY-PROCESSOR
# Connects to: GCP destination via VPN/interconnect

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/production_aws_config.json"

echo " AWS Multi-Cloud VPP Chain Deployment"
echo "========================================"
echo "Deploying: VXLAN-PROCESSOR → SECURITY-PROCESSOR"
echo "Target: GCP destination via cross-cloud connection"
echo ""

# Verify we're running as root
if [[ $EUID -ne 0 ]]; then
   echo " ERROR: This script must be run as root (sudo)" 
   exit 1
fi

# Verify configuration file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo " ERROR: AWS config file not found: $CONFIG_FILE"
    echo "   Run: python3 configure_multicloud_deployment.py first"
    exit 1
fi

echo " Configuration file found: $CONFIG_FILE"

# Verify AWS environment
echo ""
echo "  Verifying AWS Environment..."

# Check if we're on AWS
if ! curl -s --max-time 5 http://169.254.169.254/latest/meta-data/instance-id &> /dev/null; then
    echo "  WARNING: Cannot reach AWS metadata service"
    echo "   This may not be an AWS instance"
    read -p "   Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    AWS_INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    echo " AWS Instance: $AWS_INSTANCE_ID in $AWS_REGION"
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo " Installing Docker..."
    apt-get update -qq
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    echo " Docker installed"
else
    echo " Docker already installed"
fi

# Check Python dependencies
echo ""
echo "  Installing Dependencies..."
if ! python3 -c "import docker, scapy, json" &> /dev/null; then
    echo " Installing Python dependencies..."
    apt-get update -qq
    apt-get install -y python3-pip
    pip3 install docker scapy-python3
    echo " Python dependencies installed"
else
    echo " Python dependencies already installed"
fi

# Backup network configuration
echo ""
echo "  Creating Network Backup..."
BACKUP_DIR="/tmp/aws_vpp_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

ip addr show > "$BACKUP_DIR/ip_addr.txt"
ip route show > "$BACKUP_DIR/ip_route.txt"
ip link show > "$BACKUP_DIR/ip_link.txt"
if command -v brctl &> /dev/null; then
    brctl show > "$BACKUP_DIR/brctl_show.txt" 2>/dev/null || true
fi
iptables -t nat -L > "$BACKUP_DIR/iptables_nat.txt" 2>/dev/null || true

echo " Network state backed up to: $BACKUP_DIR"

# Clean up any existing VPP containers
echo ""
echo "  Cleaning Up Existing Containers..."
python3 "$SCRIPT_DIR/src/main.py" cleanup 2>/dev/null || true
echo " Cleanup complete"

# Check required interfaces (from config)
echo ""
echo "  Verifying Network Interfaces..."

# Parse config to get interface names (basic check)
if python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    
aws_config = config['modes'][config['default_mode']]
host_integration = None

for network in aws_config.get('networks', []):
    if 'host_integration' in network:
        host_integration = network['host_integration']
        break

if host_integration:
    interface = host_integration.get('interface', 'ens5')
    bridge = host_integration.get('bridge', 'br0') 
    vxlan = host_integration.get('vxlan_interface', 'vxlan1')
    
    print(f'Checking interface: {interface}')
    print(f'Checking bridge: {bridge}')
    print(f'Checking VXLAN: {vxlan}')
else:
    print('Using defaults: ens5, br0, vxlan1')
" 2>/dev/null; then
    echo " Configuration parsed successfully"
else
    echo "  Could not parse configuration, using defaults"
fi

# Deploy AWS VPP chain
echo ""
echo "  Deploying AWS VPP Chain..."
echo "   Containers: vxlan-processor + security-processor"
echo "   Configuration: $CONFIG_FILE"
echo ""

if python3 "$SCRIPT_DIR/src/main.py" setup --config "$CONFIG_FILE" --force; then
    echo ""
    echo " AWS VPP chain deployed successfully!"
else
    echo ""
    echo " Deployment failed. Check logs above."
    exit 1
fi

# Verify deployment
echo ""
echo "  Verifying AWS Deployment..."

echo ""
echo "Container Status:"
docker ps --filter "name=vxlan-processor\|security-processor" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "Docker Networks:"
docker network ls | grep -E "aws.*cloud|vxlan.*processing|cross.*cloud" || echo "No VPP networks found yet (may still be initializing)"

echo ""
echo "VPP Status Check:"
sleep 5  # Give VPP time to initialize

echo " VXLAN Processor Status:"
if docker exec vxlan-processor vppctl show interface 2>/dev/null; then
    echo " VXLAN Processor VPP running"
else
    echo "  VXLAN Processor VPP not ready yet"
fi

echo ""
echo " Security Processor Status:"  
if docker exec security-processor vppctl show interface 2>/dev/null; then
    echo " Security Processor VPP running"
else
    echo "  Security Processor VPP not ready yet"
fi

# Cross-cloud connectivity check
echo ""
echo "  Cross-Cloud Connectivity Check..."

# Extract GCP target from config
GCP_TARGET=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
aws_config = config['modes'][config['default_mode']]
cross_cloud = aws_config.get('cross_cloud', {})
print(cross_cloud.get('target_ip', 'unknown'))
" 2>/dev/null)

if [[ "$GCP_TARGET" != "unknown" && "$GCP_TARGET" != "" ]]; then
    echo " Target GCP IP: $GCP_TARGET"
    echo " Testing connectivity..."
    
    # Test basic connectivity
    if ping -c 3 -W 5 "$GCP_TARGET" &> /dev/null; then
        echo " Can reach GCP target: $GCP_TARGET"
    else
        echo "  Cannot reach GCP target: $GCP_TARGET"
        echo "   This is expected if GCP side is not deployed yet"
        echo "   Or if VPN/interconnect is not configured"
    fi
else
    echo "  GCP target IP not found in config"
fi

# Host network integration status
echo ""
echo "  Host Network Integration Status..."

echo "Current network interfaces:"
ip -br addr | grep -E "ens5|ens6|br0|vxlan" || echo "Standard interfaces not found"

echo ""
echo "Current routing table:"
ip route | head -10

# Final status
echo ""
echo " AWS VPP Chain Deployment Complete!"
echo "====================================="
echo ""
echo " Deployed Components:"
echo "   • VXLAN-PROCESSOR: Handles VXLAN decapsulation + BVI L2→L3"
echo "   • SECURITY-PROCESSOR: Performs NAT44 + IPsec + Fragmentation"
echo ""
echo " Cross-Cloud Status:"
echo "   • Target GCP IP: ${GCP_TARGET:-'Not configured'}"
echo "   • Connectivity: Check VPN/interconnect configuration"
echo ""
echo " Next Steps:"
echo "   1. Deploy GCP side: sudo ./deploy_gcp_multicloud.sh"
echo "   2. Configure VPN/interconnect between AWS and GCP"
echo "   3. Run diagnostics: python3 cross_cloud_diagnostics.py"
echo ""
echo " Management Commands:"
echo "   Status:    python3 src/main.py status"
echo "   Debug:     python3 src/main.py debug vxlan-processor '<command>'"
echo "   Debug:     python3 src/main.py debug security-processor '<command>'"
echo "   Cleanup:   python3 src/main.py cleanup"
echo ""
echo "Backup Location: $BACKUP_DIR"
echo ""

# Save deployment info
cat > /tmp/aws_multicloud_deployment.info << EOF
Deployment Time: $(date)
Instance ID: ${AWS_INSTANCE_ID:-'Unknown'}
Region: ${AWS_REGION:-'Unknown'}
Config File: $CONFIG_FILE
Backup Dir: $BACKUP_DIR
Target GCP IP: ${GCP_TARGET:-'Not configured'}
Status: Deployed
EOF

echo "  Deployment info saved to: /tmp/aws_multicloud_deployment.info"
echo ""