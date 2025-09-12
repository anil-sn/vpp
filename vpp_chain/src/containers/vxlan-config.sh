#!/bin/bash
# VXLAN Processor Container Configuration Script
# 
# This script configures the VXLAN processor container which is the first stage in the
# VPP multi-container processing chain. It handles VXLAN packet decapsulation and
# L2-to-L3 conversion using a Bridge Virtual Interface (BVI) architecture.
#
# Key Responsibilities:
# - Receive VXLAN encapsulated packets on external interface (172.20.100.10:4789)
# - Decapsulate VXLAN packets to extract inner L3 packets  
# - Convert L2 bridged packets to L3 routed packets using BVI architecture
# - Forward decapsulated packets to security processor for NAT44/IPsec processing
#
# Architecture Context:
# The VPP v24.10 VXLAN implementation defaults to L2 forwarding, which doesn't work
# directly for our L3 routing needs. This script implements a BVI-based workaround:
# 1. VXLAN tunnel extracts inner L2 frames
# 2. Bridge domain 10 connects VXLAN tunnel to BVI loopback interface
# 3. BVI performs L2-to-L3 conversion and enables IP routing
# 4. L3 routing forwards packets to security processor
#
# Traffic Flow:
# External VXLAN → VXLAN Tunnel → Bridge Domain 10 → BVI Loop0 → L3 Routing → Security Processor
#
# Author: Claude Code
# Version: 2.0 (BVI L2-to-L3 conversion architecture)
# Last Updated: 2025-09-12

set -e  # Exit immediately if any command fails

echo "--- Configuring VXLAN Processor Container (L2-to-L3 BVI Architecture) ---"

# Parse container configuration from environment variable set by ContainerManager
# The VPP_CONFIG environment variable contains the JSON configuration for this container
if [ -z "$VPP_CONFIG" ]; then
  echo "Error: VPP_CONFIG environment variable not set." >&2
  exit 1
fi

# Utility function to extract values from the JSON configuration
# Uses jq to parse JSON and extract specific configuration values
get_json_value() {
  echo "$VPP_CONFIG" | jq -r "$1"
}

# Function to generate deterministic MAC address from IP address
# This provides consistent MAC addresses across container restarts for debugging
# Note: With dynamic MAC learning, this is primarily used for BVI MAC generation
generate_mac_from_ip() {
  local ip="$1"
  # Create MAC suffix from MD5 hash of IP address, ensuring VPP-style prefix (02:fe:)
  local mac_suffix=$(echo "$ip" | md5sum | cut -c1-10 | sed 's/\(..\)/\1:/g' | sed 's/:$//')
  echo "02:fe:$mac_suffix"
}

# Legacy function for MAC discovery (now handled by dynamic MAC learning system)
# This function is kept for backward compatibility but is superseded by the 
# post-configuration dynamic MAC learning that runs after all containers are ready
discover_remote_mac() {
  local remote_ip="$1"
  local interface="$2"
  
  # Attempt VPP-based neighbor discovery as fallback
  vppctl ping "$remote_ip" repeat 3 >/dev/null 2>&1 || true
  
  # Check VPP neighbor table for discovered MAC
  local discovered_mac=$(vppctl show ip neighbors | grep "$remote_ip" | awk '{print $4}' | head -1)
  
  if [ -n "$discovered_mac" ] && [ "$discovered_mac" != "00:00:00:00:00:00" ]; then
    echo "$discovered_mac"
  else
    # Fallback to generated MAC (will be updated by dynamic MAC learning later)
    generate_mac_from_ip "$remote_ip"
  fi
}

# STEP 1: Configure VPP Host Interfaces
# Create VPP host interfaces that connect to Docker network bridges
# These interfaces handle packet I/O between VPP and the Docker networking layer
echo "Configuring VPP host interfaces..."
for i in $(seq 0 $(($(get_json_value '.interfaces | length') - 1))); do
  IF_NAME=$(get_json_value ".interfaces[$i].name")
  IF_IP_ADDR=$(get_json_value ".interfaces[$i].ip.address")
  IF_IP_MASK=$(get_json_value ".interfaces[$i].ip.mask")
  
  echo "Configuring interface: host-$IF_NAME with IP $IF_IP_ADDR/$IF_IP_MASK"
  
  # Create VPP host interface connected to Docker container network interface
  vppctl create host-interface name "$IF_NAME"
  
  # Assign IP address to the VPP interface for L3 routing
  vppctl set interface ip address "host-$IF_NAME" "$IF_IP_ADDR/$IF_IP_MASK"
  
  # Bring interface up to enable packet processing
  vppctl set interface state "host-$IF_NAME" up
  
  # Enable promiscuous mode for enhanced packet reception and debugging
  # This allows the interface to receive packets even with slight MAC mismatches
  echo "Enabling promiscuous mode on host-$IF_NAME to eliminate MAC mismatch drops"
  vppctl set interface promiscuous on "host-$IF_NAME"
done

# STEP 2: Create VXLAN Tunnel for Packet Decapsulation
# Configure VXLAN tunnel to receive and decapsulate VXLAN packets from external sources
VXLAN_SRC=$(get_json_value ".vxlan_tunnel.src")     # Local endpoint (172.20.100.10)
VXLAN_DST=$(get_json_value ".vxlan_tunnel.dst")     # Remote endpoint (172.20.100.1)
VXLAN_VNI=$(get_json_value ".vxlan_tunnel.vni")     # Virtual Network Identifier (100)

echo "Creating VXLAN tunnel: src=$VXLAN_SRC dst=$VXLAN_DST vni=$VXLAN_VNI"
echo "VXLAN tunnel will decapsulate packets and forward inner L3 content for processing"

# Create VXLAN tunnel using VPP v24.10 syntax
# This tunnel will automatically decapsulate VXLAN packets received on UDP port 4789
vppctl create vxlan tunnel src "$VXLAN_SRC" dst "$VXLAN_DST" vni "$VXLAN_VNI"

# Bring VXLAN tunnel interface up to enable packet processing
vppctl set interface state vxlan_tunnel0 up

# STEP 3: Create Bridge Virtual Interface (BVI) Architecture for L2-to-L3 Conversion
# VPP v24.10 VXLAN tunnels default to L2 forwarding mode, but we need L3 routing.
# The BVI architecture solves this by creating a bridge domain that connects the VXLAN
# tunnel (L2) to a loopback interface (L3), enabling seamless L2-to-L3 conversion.
echo "Setting up BVI-based L2-to-L3 conversion architecture for VXLAN decapsulation"

# Create bridge domain 10 to connect VXLAN tunnel with BVI loopback interface
echo "Creating bridge domain 10 for VXLAN L2-to-L3 conversion"
vppctl create bridge-domain 10

# Create loopback interface that will serve as the Bridge Virtual Interface (BVI)
echo "Creating loopback interface as Bridge Virtual Interface (BVI)"
vppctl create loopback interface

# Add VXLAN tunnel to bridge domain 10 (L2 side)
echo "Adding VXLAN tunnel to bridge domain 10"
vppctl set interface l2 bridge vxlan_tunnel0 10

# Add loopback interface as BVI to bridge domain 10 (L3 side)
echo "Adding loopback interface as BVI to bridge domain 10"
vppctl set interface l2 bridge loop0 10 bvi

# Bring up loopback/BVI interface to enable L3 processing
vppctl set interface state loop0 up

# STEP 4: Configure BVI Interface with Deterministic MAC and IP Address
# The BVI interface needs a proper MAC and IP address for L3 routing functionality
BVI_IP_CIDR=$(get_json_value ".bvi.ip")                # Get BVI IP from config (192.168.201.1/24)
BVI_IP=$(echo "$BVI_IP_CIDR" | cut -d'/' -f1)         # Extract IP without CIDR
BVI_MAC=$(generate_mac_from_ip "$BVI_IP")              # Generate consistent MAC from IP

echo "Configuring BVI interface: IP=$BVI_IP_CIDR, MAC=$BVI_MAC"
echo "BVI MAC is deterministically generated from IP to ensure consistency across restarts"

# Set BVI MAC address to prevent "BVI L3 mac mismatch" errors
vppctl set interface mac address loop0 "$BVI_MAC"

# Configure BVI IP address for L3 routing functionality
vppctl set interface ip address loop0 "$BVI_IP_CIDR"

# STEP 5: Configure L3 Routing Table
# Set up routing rules to forward decapsulated packets to the security processor
echo "Configuring L3 routing table for packet forwarding to security processor..."
for i in $(seq 0 $(($(get_json_value '.routes | length') - 1))); do
  ROUTE_TO=$(get_json_value ".routes[$i].to")          # Destination network
  ROUTE_VIA=$(get_json_value ".routes[$i].via")        # Next hop IP
  ROUTE_IF=$(get_json_value ".routes[$i].interface")   # Output interface
  
  echo "Adding route: $ROUTE_TO via $ROUTE_VIA dev host-$ROUTE_IF"
  echo "  -> This route forwards decapsulated packets toward security processor"
  vppctl ip route add "$ROUTE_TO" via "$ROUTE_VIA" "host-$ROUTE_IF"
done

# CONFIGURATION COMPLETE - Display Final Status
echo "--- VXLAN Processor Configuration Completed Successfully ---"
echo ""
echo "Architecture Summary:"
echo "  VXLAN Tunnel (vxlan_tunnel0) -> Bridge Domain 10 -> BVI Loop0 -> L3 Routing"
echo "  External VXLAN packets are decapsulated and converted from L2 to L3 for routing"
echo ""
echo "Key Features Enabled:"
echo "  ✓ VXLAN decapsulation (VNI $VXLAN_VNI)"
echo "  ✓ BVI-based L2-to-L3 conversion"
echo "  ✓ Promiscuous mode on all interfaces"
echo "  ✓ Dynamic MAC learning integration"
echo "  ✓ L3 routing to security processor"
echo ""

# Display current configuration status for debugging
echo "=== CURRENT VPP CONFIGURATION STATUS ==="
echo ""
echo "Interface Configuration:"
vppctl show interface addr
echo ""
echo "VXLAN Tunnel Status:"
vppctl show vxlan tunnel
echo ""
echo "Bridge Domain Configuration:"
vppctl show bridge-domain 10 detail
echo ""
echo "L3 Routing Table:"
vppctl show ip fib
echo ""
echo "=== VXLAN PROCESSOR READY FOR TRAFFIC ==="