#!/bin/bash
set -e

echo "--- Configuring Destination Container (L3 MAC FIXED) ---"

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
  
  # *** CRITICAL FIX: Enable promiscuous mode to accept packets with different MACs ***
  echo "*** FIXING L3 MAC MISMATCH: Enabling promiscuous mode on host-$IF_NAME ***"
  vppctl set interface promiscuous on "host-$IF_NAME"
done

# Add secondary IP for NAT-translated traffic (172.20.102.10)
echo "Adding secondary IP for NAT-translated traffic: 172.20.102.10/24"
vppctl set interface ip address host-eth0 172.20.102.10/24

# *** CRITICAL FIX: Configure ARP entries to handle upstream MAC addresses ***
echo "*** CONFIGURING STATIC ARP ENTRIES TO PREVENT MAC MISMATCH ***"

# Get the MAC address of the security-processor's eth1 interface
# This should match what security-processor uses when sending packets
SECURITY_PROCESSOR_MAC="02:42:ac:14:66:14"  # Docker typically assigns this pattern
SECURITY_PROCESSOR_IP="172.20.102.10"       # security-processor's eth1 IP

# Configure static ARP entry for security-processor
echo "Adding static ARP entry: $SECURITY_PROCESSOR_IP -> $SECURITY_PROCESSOR_MAC"
vppctl set ip arp static host-eth0 "$SECURITY_PROCESSOR_IP" "$SECURITY_PROCESSOR_MAC"

# *** ADDITIONAL FIX: Disable L3 MAC matching for this interface ***
echo "*** DISABLING STRICT L3 MAC MATCHING ***"
# Allow packets with any source MAC to be processed at L3
vppctl set interface feature host-eth0 ethernet-input arc device-input

# Configure TAP interface
TAP_ID=$(get_json_value ".tap_interface.id")
TAP_NAME=$(get_json_value ".tap_interface.name")
TAP_IP=$(get_json_value ".tap_interface.ip")
TAP_LINUX_IP=$(get_json_value ".tap_interface.linux_ip")
TAP_RX_MODE=$(get_json_value ".tap_interface.rx_mode")

echo "Creating TAP interface: $TAP_NAME"
vppctl create tap id "$TAP_ID" host-if-name "$TAP_NAME"
vppctl set interface ip address tap0 "$TAP_IP"
vppctl set interface state tap0 up

# Set TAP interface to interrupt mode to reduce CPU usage
if [ "$TAP_RX_MODE" = "interrupt" ]; then
  echo "Setting TAP interface to interrupt mode"
  vppctl set interface rx-mode tap0 interrupt
fi

# Configure Linux side of TAP interface
echo "Configuring Linux TAP interface"
ip addr add "$TAP_LINUX_IP" dev "$TAP_NAME" || echo "TAP IP already configured"
ip link set "$TAP_NAME" up || echo "TAP interface already up"

# Configure IPsec decryption (incoming)
if [ "$(get_json_value '.ipsec')" != "null" ]; then
  echo "Configuring IPsec decryption..."
  
  SA_IN_ID=$(get_json_value ".ipsec.sa_in.id")
  SA_IN_SPI=$(get_json_value ".ipsec.sa_in.spi")
  SA_IN_CRYPTO_ALG=$(get_json_value ".ipsec.sa_in.crypto_alg")
  SA_IN_CRYPTO_KEY=$(get_json_value ".ipsec.sa_in.crypto_key")
  
  LOCAL_IP_TUNNEL=$(get_json_value ".ipsec.tunnel.local_ip")
  
  # Create incoming SA for decryption
  vppctl ipsec sa add "$SA_IN_ID" spi "$SA_IN_SPI" esp crypto-alg "$SA_IN_CRYPTO_ALG" crypto-key "$SA_IN_CRYPTO_KEY"
  
  # Create IPIP tunnel for receiving encrypted traffic
  echo "Creating IPIP tunnel interface for IPsec decryption"
  TUNNEL_SRC=$(get_json_value ".ipsec.tunnel.src // \"172.20.102.20\"")
  TUNNEL_DST=$(get_json_value ".ipsec.tunnel.dst // \"172.20.101.20\"")
  
  vppctl create ipip tunnel src "$TUNNEL_SRC" dst "$TUNNEL_DST"
  vppctl set interface ip address ipip0 "$LOCAL_IP_TUNNEL"
  vppctl set interface state ipip0 up
  
  # Apply IPsec protection for decryption
  vppctl ipsec tunnel protect ipip0 sa-in "$SA_IN_ID"
fi

# *** CRITICAL FIX: Add specific routes for fragmented packets ***
echo "*** CONFIGURING ROUTES FOR FRAGMENTED PACKET REASSEMBLY ***"

# Route fragmented packets from security-processor to reassembly
vppctl ip route add 10.10.10.0/24 via tap0
vppctl ip route add 172.20.102.0/24 via tap0

# Configure routes
for i in $(seq 0 $(($(get_json_value '.routes | length') - 1))); do
  ROUTE_TO=$(get_json_value ".routes[$i].to")
  ROUTE_VIA=$(get_json_value ".routes[$i].via")
  
  if [ "$ROUTE_VIA" = "tap0" ]; then
    echo "Adding route: $ROUTE_TO via tap0"
    vppctl ip route add "$ROUTE_TO" via tap0
  elif [ "$ROUTE_VIA" = "ipip0" ]; then
    echo "Adding route: $ROUTE_TO via ipip0"
    vppctl ip route add "$ROUTE_TO" via ipip0
  else
    ROUTE_IF=$(get_json_value ".routes[$i].interface // \"eth0\"")
    echo "Adding route: $ROUTE_TO via $ROUTE_VIA dev host-$ROUTE_IF"
    vppctl ip route add "$ROUTE_TO" via "$ROUTE_VIA" "host-$ROUTE_IF"
  fi
done

# *** ENABLE IP REASSEMBLY FOR FRAGMENTED PACKETS ***
echo "*** ENABLING IP REASSEMBLY FOR FRAGMENTED PACKETS ***"
vppctl set interface feature host-eth0 ip4-reassembly arc ip4-unicast

# Start packet capture if specified
PCAP_FILE=$(get_json_value ".tap_interface.pcap_file")
if [ "$PCAP_FILE" != "null" ] && [ -n "$PCAP_FILE" ]; then
  echo "Starting packet capture on TAP interface: $PCAP_FILE"
  vppctl pcap trace on max 10000 file "$PCAP_FILE" buffer-trace tap-input 1000
fi

echo "--- Destination L3-FIXED configuration completed ---"
echo "Interface configuration:"
vppctl show interface addr
echo ""
echo "*** PROMISCUOUS MODE STATUS ***"
vppctl show interface | grep -A 5 "host-eth0"
echo ""
echo "*** ARP TABLE (should show static entries) ***"
vppctl show ip arp
echo ""
echo "TAP interface status:"
vppctl show interface tap0
echo ""
if [ "$(get_json_value '.ipsec')" != "null" ]; then
  echo "IPsec status:"
  vppctl show ipsec sa
  echo ""
  echo "IPIP tunnel status:"
  vppctl show ipip tunnel
  echo ""
fi
echo "*** L3 ROUTING TABLE ***"
vppctl show ip fib
echo ""
echo "Linux TAP interface status:"
ip addr show "$TAP_NAME" || echo "TAP interface not visible in Linux"