#!/bin/bash
set -e

echo "--- Configuring Security Processor Container (NAT44 + IPsec + Fragmentation) ---"

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

# Create IPsec Security Associations
vppctl ipsec sa add "$SA_OUT_ID" spi "$SA_OUT_SPI" esp crypto-alg "$SA_OUT_CRYPTO_ALG" crypto-key "$SA_OUT_CRYPTO_KEY" tunnel-src "$TUNNEL_SRC" tunnel-dst "$TUNNEL_DST"
vppctl ipsec sa add "$SA_IN_ID" spi "$SA_IN_SPI" esp crypto-alg "$SA_IN_CRYPTO_ALG" crypto-key "$SA_IN_CRYPTO_KEY" tunnel-src "$TUNNEL_DST" tunnel-dst "$TUNNEL_SRC"

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