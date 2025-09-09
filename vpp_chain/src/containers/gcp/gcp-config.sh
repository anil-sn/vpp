#!/bin/bash
set -e

echo "--- Configuring GCP Container ---"

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

# Create TAP interface
TAP_ID=$(get_json_value ".tap_interface.id")
TAP_NAME=$(get_json_value ".tap_interface.name")
TAP_IP=$(get_json_value ".tap_interface.ip")
LINUX_IP=$(get_json_value ".tap_interface.linux_ip")
PCAP_FILE=$(get_json_value ".tap_interface.pcap_file")

vppctl create tap id "$TAP_ID" host-if-name "$TAP_NAME"
vppctl set interface ip address tap"$TAP_ID" "$TAP_IP"
vppctl set interface state tap"$TAP_ID" up
# Set TAP interface to interrupt mode to prevent high CPU usage
vppctl set interface rx-mode tap"$TAP_ID" interrupt

# Configure routes
for i in $(seq 0 $(($(get_json_value '.routes | length') - 1))); do
  ROUTE_TO=$(get_json_value ".routes[$i].to")
  ROUTE_VIA=$(get_json_value ".routes[$i].via")
  
  if [[ $ROUTE_VIA == "tap0" ]]; then
    vppctl ip route add "$ROUTE_TO" via tap0
  else
    vppctl ip route add "$ROUTE_TO" via "$ROUTE_VIA"
  fi
done

# Configure Linux side of TAP interface
ip addr add "$LINUX_IP" dev "$TAP_NAME" || echo "TAP already configured"
ip link set "$TAP_NAME" up || echo "TAP already up"

# Start packet capture service on TAP interface
tcpdump -i "$TAP_NAME" -w "$PCAP_FILE" &
TCPDUMP_PID=$!

echo "--- GCP configuration completed ---"
vppctl show interface addr
vppctl show ip fib
ip addr show "$TAP_NAME"
echo "--- Packet capture started on TAP interface (PID: $TCPDUMP_PID) ---"