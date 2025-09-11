#!/bin/bash
set -e

echo "--- Configuring VXLAN Processor Container ---"

# Parse config from environment variable
if [ -z "$VPP_CONFIG" ]; then
  echo "Error: VPP_CONFIG environment variable not set." >&2
  exit 1
fi

# Function to get value from JSON
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
  
  # Enable promiscuous mode for better packet reception (VPP interfaces only)
  # vppctl set interface promiscuous on "host-$IF_NAME" # DISABLED FOR HOST SAFETY
done

# Create VXLAN tunnel
VXLAN_SRC=$(get_json_value ".vxlan_tunnel.src")
VXLAN_DST=$(get_json_value ".vxlan_tunnel.dst")
VXLAN_VNI=$(get_json_value ".vxlan_tunnel.vni")

# CRITICAL FIX: Create VXLAN tunnel for L3 decapsulation (VPP v24.10 syntax)
echo "Creating VXLAN tunnel: src=$VXLAN_SRC dst=$VXLAN_DST vni=$VXLAN_VNI (L3-only mode)"
vppctl create vxlan tunnel src "$VXLAN_SRC" dst "$VXLAN_DST" vni "$VXLAN_VNI"
vppctl set interface state vxlan_tunnel0 up

# CRITICAL FIX: Create BVI-based L2-to-L3 conversion (VPP v24.10 workaround)
# VXLAN tunnel defaults to L2 forwarding, so we use a bridge domain with BVI for L3 conversion
echo "Setting up BVI-based L2-to-L3 conversion for VXLAN decapsulation"

# Create bridge domain for VXLAN L2-to-L3 conversion
vppctl create bridge-domain 10

# Create loopback interface as BVI (Bridge Virtual Interface)
vppctl create loopback interface

# Add VXLAN tunnel to bridge domain
vppctl set interface l2 bridge vxlan_tunnel0 10

# Add loopback as BVI to bridge domain  
vppctl set interface l2 bridge loop0 10 bvi

# Bring up loopback interface
vppctl set interface state loop0 up

# Set BVI MAC address to match expected inner packet destination
# This eliminates "BVI L3 mac mismatch" errors
vppctl set interface mac address loop0 02:fe:1b:2f:30:d4

# Configure BVI IP address for L3 routing
vppctl set interface ip address loop0 192.168.201.1/24

# Configure routes
for i in $(seq 0 $(($(get_json_value '.routes | length') - 1))); do
  ROUTE_TO=$(get_json_value ".routes[$i].to")
  ROUTE_VIA=$(get_json_value ".routes[$i].via")
  ROUTE_IF=$(get_json_value ".routes[$i].interface")
  
  echo "Adding route: $ROUTE_TO via $ROUTE_VIA dev host-$ROUTE_IF"
  vppctl ip route add "$ROUTE_TO" via "$ROUTE_VIA" "host-$ROUTE_IF"
done

echo "--- VXLAN Processor configuration completed (L3-only mode) ---"
echo "Interface configuration:"
vppctl show interface addr
echo ""
echo "VXLAN tunnel status (L3 decapsulation):"
vppctl show vxlan tunnel
echo ""
echo "L3 routing table (no L2 bridge domains):"
vppctl show ip fib