#!/bin/bash
set -e

echo "--- Starting VPP in $HOSTNAME ---"

# Create necessary directories
mkdir -p /var/log/vpp /run/vpp /etc/vpp

# Copy startup configuration
cp /vpp-common/startup.conf /etc/vpp/startup.conf

# Start VPP with startup configuration
vpp -c /etc/vpp/startup.conf &
VPP_PID=$!

# Wait for VPP to start
sleep 10

# Test if VPP CLI is working
for i in {1..15}; do
    if vppctl show version > /dev/null 2>&1; then
        echo "VPP started successfully"
        break
    fi
    echo "Waiting for VPP to start... ($i/15)"
    sleep 2
done

# Check if VPP is responsive
if ! vppctl show version > /dev/null 2>&1; then
    echo "ERROR: VPP failed to start properly"
    echo "--- Checking VPP logs ---"
    tail -50 /var/log/vpp/vpp.log 2>/dev/null || echo "No VPP log available"
    exit 1
fi

echo "--- VPP is ready for configuration ---"

# Show VPP version and basic info
vppctl show version
vppctl show interface

# Load container-specific configuration based on hostname
case "$HOSTNAME" in
    "chain-ingress")
        echo "Loading INGRESS configuration..."
        /vpp-config/new-ingress-config.sh
        ;;
    "chain-vxlan")
        echo "Loading VXLAN configuration..."
        /vpp-config/new-vxlan-config.sh
        ;;
    "chain-nat")
        echo "Loading NAT configuration..."
        /vpp-config/new-nat-config.sh
        ;;
    "chain-ipsec")
        echo "Loading IPsec configuration..."
        /vpp-config/new-ipsec-config.sh
        ;;
    "chain-fragment")
        echo "Loading Fragment configuration..."
        /vpp-config/new-fragment-config.sh
        ;;
    "chain-gcp")
        echo "Loading GCP configuration..."
        /vpp-config/new-gcp-config.sh
        ;;
    *)
        echo "Unknown hostname: $HOSTNAME"
        ;;
esac

echo "--- Configuration completed successfully ---"

# Keep VPP running in foreground
wait $VPP_PID