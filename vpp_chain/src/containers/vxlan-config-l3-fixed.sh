#!/bin/bash
set -e

echo "--- Configuring VXLAN Processor Container (L3-ONLY - FIXED) ---"

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
done

# Create VXLAN tunnel
VXLAN_SRC=$(get_json_value ".vxlan_tunnel.src")
VXLAN_DST=$(get_json_value ".vxlan_tunnel.dst")
VXLAN_VNI=$(get_json_value ".vxlan_tunnel.vni")

echo "Creating VXLAN tunnel: src=$VXLAN_SRC dst=$VXLAN_DST vni=$VXLAN_VNI"
# *** CRITICAL FIX: Use decap-next ip4 instead of l2 ***
vppctl create vxlan tunnel src "$VXLAN_SRC" dst "$VXLAN_DST" vni "$VXLAN_VNI" decap-next ip4
vppctl set interface state vxlan_tunnel0 up

# *** CRITICAL FIX: Assign IP address to VXLAN tunnel for L3 routing ***
vppctl set interface ip address vxlan_tunnel0 10.200.0.1/30

# *** ELIMINATE L2 BRIDGE DOMAIN - THIS WAS CAUSING REFLECTION DROPS ***
# DO NOT CREATE BRIDGE DOMAIN - Use pure L3 routing instead
echo "Setting up L3 routing (NO L2 bridging to prevent reflection drops)"

# Configure L3 forwarding from VXLAN tunnel to output interface
# Route decapsulated packets based on their inner IP destination
echo "Adding L3 routes for decapsulated VXLAN traffic"

# Route for inner packet destinations (e.g., 10.10.10.0/24 from NetFlow)
NEXT_HOP_IP=$(get_json_value ".interfaces[1].ip.address")  # eth1 IP
vppctl ip route add 10.10.10.0/24 via "$NEXT_HOP_IP" host-eth1

# Default route for all other decapsulated traffic  
vppctl ip route add 0.0.0.0/0 via "$NEXT_HOP_IP" host-eth1

# *** CRITICAL: Enable IP forwarding on VXLAN tunnel interface ***
vppctl set interface feature vxlan_tunnel0 ip4-unicast arc ip4-unicast

# Configure ARP entries to prevent ARP flooding
ETH1_MAC=$(cat /sys/class/net/eth1/address)
vppctl set ip arp host-eth1 "$NEXT_HOP_IP" "$ETH1_MAC"

# Configure additional routes from config
for i in $(seq 0 $(($(get_json_value '.routes | length') - 1))); do
  ROUTE_TO=$(get_json_value ".routes[$i].to")
  ROUTE_VIA=$(get_json_value ".routes[$i].via")
  ROUTE_IF=$(get_json_value ".routes[$i].interface")
  
  echo "Adding route: $ROUTE_TO via $ROUTE_VIA dev host-$ROUTE_IF"
  vppctl ip route add "$ROUTE_TO" via "$ROUTE_VIA" "host-$ROUTE_IF"
done

echo "--- VXLAN Processor L3-ONLY configuration completed ---"
echo "Interface configuration:"
vppctl show interface addr
echo ""
echo "VXLAN tunnel status:"
vppctl show vxlan tunnel
echo ""
echo "*** NO BRIDGE DOMAINS (L2 bridging eliminated) ***"
echo ""
echo "L3 Routing table:"
vppctl show ip fib
echo ""
echo "ARP entries:"
vppctl show ip arp