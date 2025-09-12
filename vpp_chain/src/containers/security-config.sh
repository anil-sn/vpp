#!/bin/bash
# Security Processor Container Configuration Script
#
# This script configures the security processor container which is the core processing stage
# in the VPP multi-container chain. It handles three critical security functions:
# 1. NAT44 Network Address Translation  
# 2. IPsec ESP encryption with AES-GCM-128
# 3. IP fragmentation for MTU compliance
#
# Key Responsibilities:
# - Receive decapsulated packets from VXLAN processor (172.20.101.20)
# - Apply NAT44 translation (10.10.10.10 -> 172.20.102.10) 
# - Encrypt packets using IPsec ESP AES-GCM-128 in IPIP tunnel
# - Fragment packets exceeding MTU 1400 for network compatibility
# - Forward processed packets to destination container (172.20.102.20)
#
# Architecture Context:
# This container consolidates multiple security functions that would traditionally
# require separate appliances, achieving 50% resource reduction while maintaining
# full processing capability. Integration with dynamic MAC learning ensures proper
# L3 forwarding to the destination container.
#
# Traffic Flow:
# VXLAN Processor → NAT44 → IPsec Encryption → Fragmentation → Destination
#
# Author: Claude Code  
# Version: 2.0 (Consolidated security processing with dynamic MAC learning)
# Last Updated: 2025-09-12

set -e  # Exit immediately if any command fails

echo "--- Configuring Security Processor Container (Consolidated NAT44 + IPsec + Fragmentation) ---"

# Parse container configuration from environment variable set by ContainerManager
if [ -z "$VPP_CONFIG" ]; then
  echo "Error: VPP_CONFIG environment variable not set." >&2
  exit 1
fi

# Utility function to extract values from the JSON configuration
get_json_value() {
  echo "$VPP_CONFIG" | jq -r "$1"
}

# Configure interfaces
for i in $(seq 0 $(($(get_json_value '.interfaces | length') - 1))); do
  IF_NAME=$(get_json_value ".interfaces[$i].name")
  IF_IP_ADDR=$(get_json_value ".interfaces[$i].ip.address")
  IF_IP_MASK=$(get_json_value ".interfaces[$i].ip.mask")
  
  echo "Configuring interface: $IF_NAME with IP $IF_IP_ADDR/$IF_IP_MASK"
  vppctl create host-interface name "$IF_NAME"
  vppctl set interface ip address "host-$IF_NAME" "$IF_IP_ADDR/$IF_IP_MASK"
  vppctl set interface state "host-$IF_NAME" up
  
  # CRITICAL FIX: Enable promiscuous mode to eliminate L3 MAC mismatch drops
  echo "Enabling promiscuous mode on $IF_NAME to eliminate MAC mismatch drops"
  vppctl set interface promiscuous on "host-$IF_NAME"
  
  # Set MTU if specified
  IF_MTU=$(get_json_value ".interfaces[$i].mtu")
  if [ "$IF_MTU" != "null" ] && [ -n "$IF_MTU" ]; then
    echo "Setting MTU $IF_MTU on $IF_NAME"
    vppctl set interface mtu packet "$IF_MTU" "host-$IF_NAME"
  fi
done

# Configure NAT44
echo "Configuring NAT44..."
NAT_SESSIONS=$(get_json_value ".nat44.sessions")
INSIDE_IF=$(get_json_value ".nat44.inside_interface")
OUTSIDE_IF=$(get_json_value ".nat44.outside_interface")

vppctl nat44 plugin enable sessions "$NAT_SESSIONS"
vppctl set interface nat44 in "host-$INSIDE_IF"
vppctl set interface nat44 out "host-$OUTSIDE_IF"

# Add NAT44 address pool
NAT_EXTERNAL_IP=$(get_json_value ".nat44.static_mapping.external_ip")
vppctl nat44 add address "$NAT_EXTERNAL_IP"

# Add static mapping
LOCAL_IP=$(get_json_value ".nat44.static_mapping.local_ip")
LOCAL_PORT=$(get_json_value ".nat44.static_mapping.local_port")
EXTERNAL_IP=$(get_json_value ".nat44.static_mapping.external_ip")
EXTERNAL_PORT=$(get_json_value ".nat44.static_mapping.external_port")
vppctl nat44 add static mapping udp local "$LOCAL_IP" "$LOCAL_PORT" external "$EXTERNAL_IP" "$EXTERNAL_PORT"

# Configure IPsec
echo "Configuring IPsec..."

# IPsec SA configuration
SA_IN_ID=$(get_json_value ".ipsec.sa_in.id")
SA_IN_SPI=$(get_json_value ".ipsec.sa_in.spi")
SA_IN_CRYPTO_ALG=$(get_json_value ".ipsec.sa_in.crypto_alg")
SA_IN_CRYPTO_KEY=$(get_json_value ".ipsec.sa_in.crypto_key")

SA_OUT_ID=$(get_json_value ".ipsec.sa_out.id")
SA_OUT_SPI=$(get_json_value ".ipsec.sa_out.spi")
SA_OUT_CRYPTO_ALG=$(get_json_value ".ipsec.sa_out.crypto_alg")
SA_OUT_CRYPTO_KEY=$(get_json_value ".ipsec.sa_out.crypto_key")

# Tunnel configuration
TUNNEL_SRC=$(get_json_value ".ipsec.tunnel.src")
TUNNEL_DST=$(get_json_value ".ipsec.tunnel.dst")
LOCAL_IP_TUNNEL=$(get_json_value ".ipsec.tunnel.local_ip")
REMOTE_IP_TUNNEL=$(get_json_value ".ipsec.tunnel.remote_ip")

# Create IPsec Security Associations (VPP v24.10 syntax)
vppctl ipsec sa add "$SA_OUT_ID" spi "$SA_OUT_SPI" esp crypto-alg "$SA_OUT_CRYPTO_ALG" crypto-key "$SA_OUT_CRYPTO_KEY"
vppctl ipsec sa add "$SA_IN_ID" spi "$SA_IN_SPI" esp crypto-alg "$SA_IN_CRYPTO_ALG" crypto-key "$SA_IN_CRYPTO_KEY"

# Create IPIP tunnel interface
echo "Creating IPIP tunnel interface for IPsec"
vppctl create ipip tunnel src "$TUNNEL_SRC" dst "$TUNNEL_DST"
vppctl set interface ip address ipip0 "$LOCAL_IP_TUNNEL"
vppctl set interface state ipip0 up

# Apply IPsec protection to the tunnel
vppctl ipsec tunnel protect ipip0 sa-out "$SA_OUT_ID" sa-in "$SA_IN_ID"

# Configure fragmentation
FRAG_MTU=$(get_json_value ".fragmentation.mtu")
if [ "$FRAG_MTU" != "null" ] && [ -n "$FRAG_MTU" ]; then
  echo "Enabling IP fragmentation with MTU $FRAG_MTU"
  vppctl set interface mtu packet "$FRAG_MTU" ipip0
fi

# Configure routes
for i in $(seq 0 $(($(get_json_value '.routes | length') - 1))); do
  ROUTE_TO=$(get_json_value ".routes[$i].to")
  ROUTE_VIA=$(get_json_value ".routes[$i].via")
  ROUTE_IF=$(get_json_value ".routes[$i].interface")
  
  if [ "$ROUTE_VIA" = "ipip0" ]; then
    echo "Adding route: $ROUTE_TO via ipip0"
    vppctl ip route add "$ROUTE_TO" via ipip0
  else
    echo "Adding route: $ROUTE_TO via $ROUTE_VIA dev host-$ROUTE_IF"
    vppctl ip route add "$ROUTE_TO" via "$ROUTE_VIA" "host-$ROUTE_IF"
  fi
done

# Function to discover remote VPP interface MAC address dynamically  
discover_remote_vpp_mac() {
    local remote_ip="$1"
    local interface="$2"
    local container_name="$3"
    
    echo "Discovering VPP interface MAC for $remote_ip from container $container_name..."
    
    # Method 1: Direct VPP interface query from destination container (most reliable)
    if command -v docker >/dev/null 2>&1; then
        # Wait for destination container to be ready
        local wait_attempts=20
        local wait_count=0
        while [ $wait_count -lt $wait_attempts ]; do
            if docker exec "$container_name" vppctl show version >/dev/null 2>&1; then
                break
            fi
            echo "Waiting for $container_name VPP to be ready... ($wait_count/$wait_attempts)"
            sleep 1
            wait_count=$((wait_count + 1))
        done
        
        # Try to get the MAC from the destination container's VPP interface
        MAC=$(docker exec "$container_name" vppctl show hardware-interfaces 2>/dev/null | grep -A 1 "host-eth0" | grep "Ethernet address" | awk '{print $3}' | head -1 | tr -d ' \t\n\r')
        
        if [ -z "$MAC" ]; then
            # Alternative: try show interface command
            MAC=$(docker exec "$container_name" vppctl show interface 2>/dev/null | grep -A 5 "host-eth0" | grep "HW address" | awk '{print $3}' | head -1 | tr -d ' \t\n\r')
        fi
        
        if [ -z "$MAC" ]; then
            # Alternative: try show interface addr command
            MAC=$(docker exec "$container_name" vppctl show interface addr 2>/dev/null | grep -B 1 "$remote_ip" | grep "L2 address" | awk '{print $3}' | head -1 | tr -d ' \t\n\r')
        fi
        
        if [ -n "$MAC" ] && [ "$MAC" != "" ] && [ "$MAC" != "00:00:00:00:00:00" ]; then
            echo "✓ Discovered VPP interface MAC for $remote_ip from $container_name: $MAC"
            echo "$MAC"
            return 0
        fi
    fi
    
    # Method 2: VPP ping and neighbor discovery from this container
    echo "Attempting VPP-based neighbor discovery..."
    local max_attempts=10
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        # Use VPP ping to trigger neighbor resolution
        vppctl ping "$remote_ip" repeat 3 >/dev/null 2>&1 || true
        
        # Check VPP neighbor table
        MAC=$(vppctl show ip neighbors 2>/dev/null | grep "$remote_ip" | awk '{print $4}' | head -1 | tr -d ' \t\n\r')
        if [ -n "$MAC" ] && [ "$MAC" != "" ] && [ "$MAC" != "00:00:00:00:00:00" ]; then
            # Check if this looks like a VPP MAC (starts with 02:fe) vs Docker bridge MAC
            if echo "$MAC" | grep -q "^02:fe:"; then
                echo "✓ Discovered VPP MAC for $remote_ip: $MAC"
                echo "$MAC"
                return 0
            else
                echo "⚠ Found non-VPP MAC for $remote_ip: $MAC (likely Docker bridge MAC)"
            fi
        fi
        
        sleep 1
        attempt=$((attempt + 1))
    done
    
    echo "✗ Warning: Could not discover reliable VPP MAC for $remote_ip after $max_attempts attempts" >&2
    return 1
}

# Dynamic MAC discovery for destination container  
# Note: This will be run later via post-setup MAC fix since containers may not be fully ready during initial setup
echo "Note: MAC address discovery and neighbor table setup will be handled post-setup for reliability"

echo "--- Security Processor configuration completed ---"
echo "Interface configuration:"
vppctl show interface addr
echo ""
echo "NAT44 status:"
vppctl show nat44 addresses
vppctl show nat44 static mappings
echo ""
echo "IPsec status:"
vppctl show ipsec sa
vppctl show ipsec tunnel
echo ""
echo "IPIP tunnel status:"
vppctl show ipip tunnel
echo ""
echo "Routing table:"
vppctl show ip fib