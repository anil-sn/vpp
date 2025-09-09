#!/bin/bash
set -e

echo "--- Configuring NAT Container ---"

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

# Enable NAT44 plugin
NAT_SESSIONS=$(get_json_value ".nat44.sessions")
vppctl nat44 plugin enable sessions "$NAT_SESSIONS"

# Configure NAT interfaces
vppctl set interface nat44 in host-eth0
vppctl set interface nat44 out host-eth1

# Add address pool
NAT_EXTERNAL_IP=$(get_json_value ".nat44.static_mapping.external_ip")
vppctl nat44 add address "$NAT_EXTERNAL_IP"

# Add static mapping
LOCAL_IP=$(get_json_value ".nat44.static_mapping.local_ip")
LOCAL_PORT=$(get_json_value ".nat44.static_mapping.local_port")
EXTERNAL_IP=$(get_json_value ".nat44.static_mapping.external_ip")
EXTERNAL_PORT=$(get_json_value ".nat44.static_mapping.external_port")
vppctl nat44 add static mapping udp local "$LOCAL_IP" "$LOCAL_PORT" external "$EXTERNAL_IP" "$EXTERNAL_PORT"

echo "--- NAT configuration completed ---"
vppctl show interface addr
vppctl show nat44 addresses
vppctl show nat44 static mappings
vppctl show ip fib