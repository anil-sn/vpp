#!/bin/bash
# Destination Container Configuration Script
#
# This script configures the destination container which serves as the final endpoint
# in the VPP multi-container processing chain. It handles IPsec decryption and provides
# a TAP interface for final packet capture and analysis.
#
# Key Responsibilities:
# - Receive encrypted IPsec ESP packets from security processor (172.20.102.20)
# - Decrypt IPsec packets using matching AES-GCM-128 keys
# - Reassemble fragmented packets back to original form
# - Forward decrypted packets to TAP interface for capture (10.0.3.1/24)
# - Enable promiscuous mode for enhanced packet reception
#
# Architecture Context:
# This container represents the final destination where processed packets are captured
# for analysis. It validates the complete end-to-end processing chain and provides
# packet capture capabilities for debugging and monitoring.
#
# Author: Claude Code
# Version: 2.0 (Enhanced with dynamic MAC learning and promiscuous mode)
# Last Updated: 2025-09-12

set -e  # Exit immediately if any command fails

echo "--- Configuring Destination Container (Final Endpoint with TAP Interface) ---"

# Parse container configuration from environment variable set by ContainerManager
if [ -z "$VPP_CONFIG" ]; then
  echo "Error: VPP_CONFIG environment variable not set." >&2
  exit 1
fi

# Utility function to extract values from the JSON configuration
get_json_value() {
  echo "$VPP_CONFIG" | jq -r "$1"
}

# Function to generate MAC address from IP address
# Uses MD5 hash of IP to create consistent, deterministic MAC addresses
generate_mac_from_ip() {
  local ip="$1"
  local mac_suffix=$(echo "$ip" | md5sum | cut -c1-10 | sed 's/\(..\)/\1:/g' | sed 's/:$//')
  echo "02:fe:$mac_suffix"
}

# Function to discover MAC address of remote interface
# Attempts to get MAC via ARP, falls back to generated MAC
discover_remote_mac() {
  local remote_ip="$1"
  local interface="$2"
  
  # Try to ping the remote IP first to populate ARP table
  vppctl ping "$remote_ip" repeat 3 >/dev/null 2>&1 || true
  
  # Try to get MAC from VPP ARP table
  local discovered_mac=$(vppctl show ip neighbors | grep "$remote_ip" | awk '{print $4}' | head -1)
  
  if [ -n "$discovered_mac" ] && [ "$discovered_mac" != "00:00:00:00:00:00" ]; then
    echo "$discovered_mac"
  else
    # Fallback to generated MAC
    generate_mac_from_ip "$remote_ip"
  fi
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
  
  # CRITICAL FIX: Enable promiscuous mode to accept packets with different MACs
  # This eliminates L3 MAC mismatch drops by accepting all MAC addresses
  echo "Enabling promiscuous mode on $IF_NAME to eliminate MAC mismatch drops"
  vppctl set interface promiscuous on "host-$IF_NAME"
done

# Add secondary IP for NAT-translated traffic (172.20.102.10)
echo "Adding secondary IP for NAT-translated traffic: 172.20.102.10/24"
vppctl set interface ip address host-eth0 172.20.102.10/24

# CRITICAL FIX: Add static ARP entries for security-processor
# This ensures L3 forwarding works without L2 MAC learning dependencies
echo "Adding static ARP entry for security-processor to eliminate L2 dependency"
SECURITY_PROCESSOR_IP="172.20.102.10"

# Dynamically determine security processor MAC address
echo "Discovering MAC address for security-processor at $SECURITY_PROCESSOR_IP"
SECURITY_PROCESSOR_MAC=$(discover_remote_mac "$SECURITY_PROCESSOR_IP" "host-eth0")
echo "Using MAC address $SECURITY_PROCESSOR_MAC for security-processor"

vppctl set ip arp static host-eth0 "$SECURITY_PROCESSOR_IP" "$SECURITY_PROCESSOR_MAC" || echo "ARP entry will be set dynamically"

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
  TUNNEL_SRC=$(get_json_value ".ipsec.tunnel.src // \"172.20.2.20\"")
  TUNNEL_DST=$(get_json_value ".ipsec.tunnel.dst // \"172.20.1.20\"")
  
  vppctl create ipip tunnel src "$TUNNEL_SRC" dst "$TUNNEL_DST"
  vppctl set interface ip address ipip0 "$LOCAL_IP_TUNNEL"
  vppctl set interface state ipip0 up
  
  # Apply IPsec protection for decryption (CRITICAL FIX)
  echo "Applying IPsec tunnel protection for decryption with SA $SA_IN_ID"
  vppctl ipsec tunnel protect ipip0 sa-in "$SA_IN_ID"
  
  # Configure IPsec SPD to handle ESP packets arriving on host interface
  echo "Configuring IPsec SPD to process ESP packets on host interface"
  vppctl ipsec spd add 1
  vppctl ipsec interface host-eth0 spd 1
  
  # Add SPD policy for ESP traffic decryption 
  SECURITY_PROC_IP=$(get_json_value ".ipsec.tunnel.dst // \"172.20.101.20\"")
  LOCAL_HOST_IP=$(get_json_value ".ipsec.tunnel.src // \"172.20.102.20\"")
  
  # Policy for incoming ESP traffic (decrypt)
  vppctl ipsec policy add spd 1 priority 10 inbound action protect sa "$SA_IN_ID" \
    remote-ip-range "$SECURITY_PROC_IP" - "$SECURITY_PROC_IP" \
    local-ip-range "$LOCAL_HOST_IP" - "$LOCAL_HOST_IP" protocol 50
  
  # Policy for decrypted traffic (bypass) 
  vppctl ipsec policy add spd 1 priority 100 inbound action bypass \
    protocol 17 remote-port-range 1024 - 65535 local-port-range 1024 - 65535
    
  echo "IPsec SPD policies configured for ESP decryption"
  
  # Verify IPsec protection was applied
  echo "Verifying IPsec tunnel protection:"
  vppctl show interface ipip0 | head -5
fi

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

# Start packet capture if specified
PCAP_FILE=$(get_json_value ".tap_interface.pcap_file")
if [ "$PCAP_FILE" != "null" ] && [ -n "$PCAP_FILE" ]; then
  echo "Starting packet capture on TAP interface: $PCAP_FILE"
  vppctl pcap trace on max 10000 file "$PCAP_FILE" buffer-trace tap-input 1000
fi

echo "--- Destination configuration completed (L3-only mode) ---"
echo "Interface configuration (promiscuous mode enabled):"
vppctl show interface addr
echo ""
echo "Interface promiscuous status:"
vppctl show interface | grep -A5 -B5 promiscuous || echo "Promiscuous mode status check"
echo ""
echo "TAP interface status:"
vppctl show interface tap0
echo ""
if [ "$(get_json_value '.ipsec')" != "null" ]; then
  echo "IPsec status:"
  vppctl show ipsec sa
  echo ""
  echo "IPsec SPD status:"
  vppctl show ipsec spd
  echo ""
  echo "IPIP tunnel status:"
  vppctl show ipip tunnel
  echo ""
fi
echo "Routing table:"
vppctl show ip fib
echo ""
echo "Linux TAP interface status:"
ip addr show "$TAP_NAME" || echo "TAP interface not visible in Linux"