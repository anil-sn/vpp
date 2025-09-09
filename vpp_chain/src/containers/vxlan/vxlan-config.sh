#!/bin/bash
set -e

echo "--- Configuring VXLAN Container ---"

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
  
  vppctl create host-interface name "$IF_NAME"
  vppctl set interface ip address "host-$IF_NAME" "$IF_IP_ADDR/$IF_IP_MASK"
  vppctl set interface state "host-$IF_NAME" up
done

# Create VXLAN tunnel
VXLAN_SRC=$(get_json_value ".vxlan_tunnel.src")
VXLAN_DST=$(get_json_value ".vxlan_tunnel.dst")
VXLAN_VNI=$(get_json_value ".vxlan_tunnel.vni")
vppctl create vxlan tunnel src "$VXLAN_SRC" dst "$VXLAN_DST" vni "$VXLAN_VNI"
vppctl set interface state vxlan_tunnel0 up

# Configure routes
for i in $(seq 0 $(($(get_json_value '.routes | length') - 1))); do
  ROUTE_TO=$(get_json_value ".routes[$i].to")
  ROUTE_VIA=$(get_json_value ".routes[$i].via")
  ROUTE_IF=$(get_json_value ".routes[$i].interface")
  
  vppctl ip route add "$ROUTE_TO" via "$ROUTE_VIA" "host-$ROUTE_IF"
done

echo "--- VXLAN configuration completed ---"
vppctl show interface addr
vppctl show vxlan tunnel
vppctl show ip fib