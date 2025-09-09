#!/bin/bash
set -e

echo "--- Configuring IPsec Container ---"

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

# Configure IPsec
SA_IN_ID=$(get_json_value ".ipsec.sa_in.id")
SA_IN_SPI=$(get_json_value ".ipsec.sa_in.spi")
SA_IN_CRYPTO_ALG=$(get_json_value ".ipsec.sa_in.crypto_alg")
SA_IN_CRYPTO_KEY=$(get_json_value ".ipsec.sa_in.crypto_key")

SA_OUT_ID=$(get_json_value ".ipsec.sa_out.id")
SA_OUT_SPI=$(get_json_value ".ipsec.sa_out.spi")
SA_OUT_CRYPTO_ALG=$(get_json_value ".ipsec.sa_out.crypto_alg")
SA_OUT_CRYPTO_KEY=$(get_json_value ".ipsec.sa_out.crypto_key")

_TUNNEL_SRC=$(get_json_value ".ipsec.tunnel.src")
_TUNNEL_DST=$(get_json_value ".ipsec.tunnel.dst")
_TUNNEL_LOCAL_IP=$(get_json_value ".ipsec.tunnel.local_ip")

vppctl ipsec sa add "$SA_OUT_ID" spi "$SA_OUT_SPI" esp \
    crypto-alg "$SA_OUT_CRYPTO_ALG" \
    crypto-key "$SA_OUT_CRYPTO_KEY"

vppctl ipsec sa add "$SA_IN_ID" spi "$SA_IN_SPI" esp \
    crypto-alg "$SA_IN_CRYPTO_ALG" \
    crypto-key "$SA_IN_CRYPTO_KEY"

vppctl create ipip tunnel src "$_TUNNEL_SRC" dst "$_TUNNEL_DST"
vppctl ipsec tunnel protect ipip0 sa-in "$SA_IN_ID" sa-out "$SA_OUT_ID"
vppctl set interface state ipip0 up
vppctl set interface ip address ipip0 "$_TUNNEL_LOCAL_IP"

# Configure routes
for i in $(seq 0 $(($(get_json_value '.routes | length') - 1))); do
  ROUTE_TO=$(get_json_value ".routes[$i].to")
  ROUTE_VIA=$(get_json_value ".routes[$i].via")
  
  if [[ $ROUTE_VIA == "ipip0" ]]; then
    vppctl ip route add "$ROUTE_TO" via ipip0
  else
    vppctl ip route add "$ROUTE_TO" via "$ROUTE_VIA"
  fi
done

echo "--- IPsec configuration completed ---"
vppctl show interface addr
vppctl show ipsec sa
vppctl show ipsec tunnel
vppctl show ip fib
