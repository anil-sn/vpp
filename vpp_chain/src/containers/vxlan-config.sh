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
  
  # Enable promiscuous mode for better packet reception
  vppctl set interface promiscuous on "host-$IF_NAME"
done

# Create VXLAN tunnel
VXLAN_SRC=$(get_json_value ".vxlan_tunnel.src")
VXLAN_DST=$(get_json_value ".vxlan_tunnel.dst")
VXLAN_VNI=$(get_json_value ".vxlan_tunnel.vni")
VXLAN_DECAP_NEXT=$(get_json_value ".vxlan_tunnel.decap_next")

echo "Creating VXLAN tunnel: src=$VXLAN_SRC dst=$VXLAN_DST vni=$VXLAN_VNI"
vppctl create vxlan tunnel src "$VXLAN_SRC" dst "$VXLAN_DST" vni "$VXLAN_VNI" decap-next "$VXLAN_DECAP_NEXT"
vppctl set interface state vxlan_tunnel0 up

# Bridge VXLAN tunnel with output interface for L2 forwarding
echo "Setting up L2 bridge for VXLAN decapsulation"
vppctl create bridge-domain 1
vppctl set interface l2 bridge vxlan_tunnel0 1
vppctl set interface l2 bridge host-eth1 1

# Configure routes
for i in $(seq 0 $(($(get_json_value '.routes | length') - 1))); do
  ROUTE_TO=$(get_json_value ".routes[$i].to")
  ROUTE_VIA=$(get_json_value ".routes[$i].via")
  ROUTE_IF=$(get_json_value ".routes[$i].interface")
  
  echo "Adding route: $ROUTE_TO via $ROUTE_VIA dev host-$ROUTE_IF"
  vppctl ip route add "$ROUTE_TO" via "$ROUTE_VIA" "host-$ROUTE_IF"
done

echo "--- VXLAN Processor configuration completed ---"
echo "Interface configuration:"
vppctl show interface addr
echo ""
echo "VXLAN tunnel status:"
vppctl show vxlan tunnel
echo ""
echo "L2 bridge domains:"
vppctl show bridge-domain
echo ""
echo "Routing table:"
vppctl show ip fib