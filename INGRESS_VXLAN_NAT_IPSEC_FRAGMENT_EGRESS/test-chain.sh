#!/bin/bash
set -e

echo "========================================"
echo "VPP Multi-Container Chain Test Suite"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test functions
test_passed() {
    echo -e "${GREEN}✓ $1${NC}"
}

test_failed() {
    echo -e "${RED}✗ $1${NC}"
    return 1
}

test_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Create required directories
test_info "Creating required directories..."
mkdir -p /tmp/vpp-logs
mkdir -p /tmp/packet-captures

# Step 1: Build and start containers
test_info "Building and starting VPP multi-container chain..."
if sudo python3 src/main.py setup --force; then
    test_passed "Container setup completed"
else
    test_failed "Container setup failed"
    exit 1
fi

sleep 30  # Allow containers to fully start

# Step 2: Check container status
test_info "Checking container status..."
if python3 src/main.py status; then
    test_passed "All containers are running"
else
    test_failed "Some containers are not running properly"
fi

# Step 3: Test connectivity
test_info "Testing inter-container connectivity..."
if sudo python3 src/main.py test --type connectivity; then
    test_passed "Connectivity tests passed"
else
    test_failed "Connectivity tests failed"
fi

# Step 4: Test traffic flow
test_info "Testing end-to-end traffic flow..."
if sudo python3 src/main.py test --type traffic; then
    test_passed "Traffic tests passed"
else
    test_failed "Traffic tests failed"
fi

# Step 5: Debug individual containers
test_info "Debugging individual containers..."

echo "--- INGRESS Container Debug ---"
sudo python3 src/main.py debug chain-ingress "show interface addr"
sudo python3 src/main.py debug chain-ingress "show ip fib"

echo "--- VXLAN Container Debug ---"
sudo python3 src/main.py debug chain-vxlan "show vxlan tunnel"
sudo python3 src/main.py debug chain-vxlan "show bridge-domain"

echo "--- NAT Container Debug ---"
sudo python3 src/main.py debug chain-nat "show nat44 static mappings"
sudo python3 src/main.py debug chain-nat "show nat44 sessions"

echo "--- IPsec Container Debug ---"
sudo python3 src/main.py debug chain-ipsec "show ipsec sa"
sudo python3 src/main.py debug chain-ipsec "show ipsec tunnel"

echo "--- Fragment Container Debug ---"
sudo python3 src/main.py debug chain-fragment "show interface"

echo "--- GCP Container Debug ---"
sudo python3 src/main.py debug chain-gcp "show interface addr"

# Step 6: Generate test traffic using Scapy
test_info "Generating VXLAN test traffic..."

cat > /tmp/generate_traffic.py << 'EOF'
#!/usr/bin/env python3
"""
VXLAN Traffic Generator for VPP Chain Testing
"""

import time
from scapy.all import *

def generate_vxlan_traffic():
    """Generate VXLAN encapsulated traffic"""
    
    print("Generating VXLAN test traffic...")
    
    # Inner IP packet (what gets decapsulated)
    inner_ip = IP(src="10.10.10.10", dst="10.0.3.1") / UDP(sport=12345, dport=2055) / Raw(b"A" * 1500)
    
    # VXLAN header
    vxlan = VXLAN(vni=100)
    
    # Outer headers
    outer_eth = Ether()
    outer_ip = IP(src="192.168.10.100", dst="192.168.10.2") / UDP(sport=54321, dport=4789)
    
    # Complete VXLAN packet
    vxlan_packet = outer_eth / outer_ip / vxlan / inner_ip
    
    print(f"Packet size: {len(vxlan_packet)} bytes")
    print("Packet summary:")
    vxlan_packet.show()
    
    # Send traffic to ingress container
    try:
        sendp(vxlan_packet, iface="docker0", count=5, inter=1)
        print("✓ VXLAN traffic sent successfully")
        return True
    except Exception as e:
        print(f"✗ Failed to send traffic: {e}")
        return False

if __name__ == "__main__":
    generate_vxlan_traffic()
EOF

chmod +x /tmp/generate_traffic.py
if sudo python3 /tmp/generate_traffic.py; then
    test_passed "VXLAN traffic generated successfully"
else
    test_failed "Failed to generate VXLAN traffic"
fi

# Step 7: Check packet captures
test_info "Checking packet captures in GCP container..."
echo "Captured packets in GCP container:"
ls -la /tmp/packet-captures/

# Step 8: Monitor chain for 30 seconds
test_info "Monitoring chain performance..."
python3 src/main.py monitor --duration 30

echo "========================================"
echo "Test Suite Completed"
echo "========================================"

# Optional cleanup prompt
echo "Would you like to clean up the containers? (y/N)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    test_info "Cleaning up containers..."
    sudo python3 src/main.py cleanup
    test_passed "Cleanup completed"
else
    test_info "Containers left running for manual inspection"
    echo "Use 'sudo python3 src/main.py cleanup' when done"
fi