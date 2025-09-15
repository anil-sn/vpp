#!/bin/bash

# GCP Multi-Cloud VPP Chain Deployment Script
# Deploys: DESTINATION processor
# Receives from: AWS VXLAN + Security processors via VPN/interconnect

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/production_gcp_config.json"

echo " GCP Multi-Cloud VPP Chain Deployment"
echo "========================================"
echo "Deploying: DESTINATION processor"
echo "Receives from: AWS processors via cross-cloud connection"
echo ""

# Verify we're running as root
if [[ $EUID -ne 0 ]]; then
   echo " ERROR: This script must be run as root (sudo)" 
   exit 1
fi

# Verify configuration file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo " ERROR: GCP config file not found: $CONFIG_FILE"
    echo "   Run: python3 configure_multicloud_deployment.py first"
    exit 1
fi

echo " Configuration file found: $CONFIG_FILE"

# Verify GCP environment
echo ""
echo "  Verifying GCP Environment..."

# Check if we're on GCP
if curl -s --max-time 5 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/id &> /dev/null; then
    GCP_INSTANCE_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/id)
    GCP_ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d'/' -f4)
    GCP_PROJECT=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
    echo " GCP Instance: $GCP_INSTANCE_ID"
    echo " Zone: $GCP_ZONE"  
    echo " Project: $GCP_PROJECT"
else
    echo "  WARNING: Cannot reach GCP metadata service"
    echo "   This may not be a GCP instance"
    read -p "   Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    GCP_INSTANCE_ID="unknown"
    GCP_ZONE="unknown"
    GCP_PROJECT="unknown"
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
BACKUP_DIR="/tmp/gcp_vpp_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

ip addr show > "$BACKUP_DIR/ip_addr.txt"
ip route show > "$BACKUP_DIR/ip_route.txt"
ip link show > "$BACKUP_DIR/ip_link.txt"
iptables -t nat -L > "$BACKUP_DIR/iptables_nat.txt" 2>/dev/null || true

echo " Network state backed up to: $BACKUP_DIR"

# Clean up any existing VPP containers
echo ""
echo "  Cleaning Up Existing Containers..."
python3 "$SCRIPT_DIR/src/main.py" cleanup 2>/dev/null || true
echo " Cleanup complete"

# Verify network configuration
echo ""
echo "  Verifying Network Configuration..."

# Check for required network access
if python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    
gcp_config = config['modes'][config['default_mode']]
cross_cloud = gcp_config.get('cross_cloud', {})
source_ip = cross_cloud.get('source_ip', '')

if source_ip:
    print(f'AWS Source IP: {source_ip}')
else:
    print('AWS source IP not configured')
" 2>/dev/null; then
    echo " Configuration parsed successfully"
else
    echo "  Could not parse configuration"
fi

# Configure GCP-specific network settings
echo ""
echo "  Configuring GCP Network Settings..."

# Enable IP forwarding for packet processing
echo 1 > /proc/sys/net/ipv4/ip_forward
echo " IP forwarding enabled"

# Configure firewall if needed (GCP-specific)
if command -v gcloud &> /dev/null; then
    echo " Checking GCP firewall rules..."
    # Note: In production, firewall rules should be configured via terraform/gcloud
    echo "  Configure VPP traffic firewall rules in GCP Console if needed"
else
    echo "  gcloud CLI not installed - firewall configuration manual"
fi

# Deploy GCP VPP destination
echo ""
echo "  Deploying GCP VPP Destination..."
echo "   Container: destination (ESP decryption + TAP delivery)"
echo "   Configuration: $CONFIG_FILE"
echo ""

if python3 "$SCRIPT_DIR/src/main.py" setup --config "$CONFIG_FILE" --force; then
    echo ""
    echo " GCP VPP destination deployed successfully!"
else
    echo ""
    echo " Deployment failed. Check logs above."
    exit 1
fi

# Verify deployment
echo ""
echo "  Verifying GCP Deployment..."

echo ""
echo "Container Status:"
docker ps --filter "name=destination" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "Docker Networks:"
docker network ls | grep -E "gcp.*cloud|cross.*cloud" || echo "No VPP networks found yet (may still be initializing)"

echo ""
echo "VPP Status Check:"
sleep 5  # Give VPP time to initialize

echo " Destination Processor Status:"
if docker exec destination vppctl show interface 2>/dev/null; then
    echo " Destination VPP running"
    
    echo ""
    echo "TAP Interface Status:"
    docker exec destination vppctl show interface tap0 2>/dev/null || echo "TAP interface not ready yet"
    
    echo ""
    echo "IPsec Configuration:"
    docker exec destination vppctl show ipsec sa 2>/dev/null || echo "IPsec not configured yet"
    
else
    echo "  Destination VPP not ready yet"
fi

# Cross-cloud connectivity check
echo ""
echo "  Cross-Cloud Connectivity Check..."

# Extract AWS source from config
AWS_SOURCE=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
gcp_config = config['modes'][config['default_mode']]
cross_cloud = gcp_config.get('cross_cloud', {})
print(cross_cloud.get('source_ip', 'unknown'))
" 2>/dev/null)

if [[ "$AWS_SOURCE" != "unknown" && "$AWS_SOURCE" != "" ]]; then
    echo " AWS Source IP: $AWS_SOURCE"
    echo " Testing connectivity..."
    
    # Test basic connectivity to AWS
    if ping -c 3 -W 5 "$AWS_SOURCE" &> /dev/null; then
        echo " Can reach AWS source: $AWS_SOURCE"
    else
        echo "  Cannot reach AWS source: $AWS_SOURCE"
        echo "   This is expected if AWS side is not deployed yet"
        echo "   Or if VPN/interconnect is not configured"
    fi
    
    # Test for incoming VPP traffic (port monitoring)
    echo ""
    echo " Monitoring for incoming VPP traffic..."
    
    # Check if we can detect any traffic patterns
    timeout 10 tcpdump -c 5 -i any host "$AWS_SOURCE" 2>/dev/null || echo "No traffic detected from AWS (normal if not sending yet)"
    
else
    echo "  AWS source IP not found in config"
fi

# TAP interface verification
echo ""
echo " TAP Interface Configuration..."

# Wait a moment for TAP to be available
sleep 2

echo "Checking for TAP interface in container:"
if docker exec destination ip addr show tap0 2>/dev/null; then
    echo " TAP interface configured in container"
    
    # Check if TAP is accessible from host
    echo ""
    echo "Host TAP interface integration:"
    if ip link show | grep -q tap0; then
        echo " TAP interface visible on host"
    else
        echo "  TAP interface container-only (normal for Docker deployment)"
    fi
else
    echo "  TAP interface not ready yet"
fi

# Final status and next steps
echo ""
echo " GCP VPP Destination Deployment Complete!"
echo "=========================================="
echo ""
echo " Deployed Components:"
echo "   • DESTINATION: IPsec decryption + packet reassembly + TAP delivery"
echo ""
echo " Cross-Cloud Status:"
echo "   • AWS Source IP: ${AWS_SOURCE:-'Not configured'}"
echo "   • Listening for encrypted traffic from AWS Security Processor"
echo ""
echo " Next Steps:"
echo "   1. Ensure AWS side is deployed: sudo ./deploy_aws_multicloud.sh"
echo "   2. Configure VPN/interconnect between AWS and GCP"  
echo "   3. Run end-to-end diagnostics: python3 cross_cloud_diagnostics.py"
echo ""
echo " Management Commands:"
echo "   Status:    python3 src/main.py status"
echo "   Debug:     python3 src/main.py debug destination '<command>'"
echo "   Cleanup:   python3 src/main.py cleanup"
echo ""
echo " Monitoring Commands:"
echo "   VPP Stats: docker exec destination vppctl show runtime"
echo "   TAP Stats: docker exec destination vppctl show interface tap0"
echo "   IPsec:     docker exec destination vppctl show ipsec sa"
echo ""
echo "Backup Location: $BACKUP_DIR"
echo ""

# Save deployment info
cat > /tmp/gcp_multicloud_deployment.info << EOF
Deployment Time: $(date)
Instance ID: ${GCP_INSTANCE_ID:-'Unknown'}
Zone: ${GCP_ZONE:-'Unknown'}
Project: ${GCP_PROJECT:-'Unknown'}
Config File: $CONFIG_FILE
Backup Dir: $BACKUP_DIR
AWS Source IP: ${AWS_SOURCE:-'Not configured'}
Status: Deployed
EOF

echo "  Deployment info saved to: /tmp/gcp_multicloud_deployment.info"

# GCP-specific final checks
echo ""
echo " GCP-Specific Verification:"

# Check internal IP configuration
INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip 2>/dev/null || echo "unknown")
if [[ "$INTERNAL_IP" != "unknown" ]]; then
    echo " GCP Internal IP: $INTERNAL_IP"
else
    echo "  Could not determine GCP internal IP"
fi

# Check for VPN gateway (if configured)
if ip route | grep -q "169.254"; then
    echo " Detected Cloud VPN routing"
else
    echo "  No Cloud VPN routes detected"
fi

echo ""
echo " Ready to receive traffic from AWS VPP chain!"
echo ""