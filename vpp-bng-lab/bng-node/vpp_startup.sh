#!/bin/bash
# =========================================================================
# VPP BNG Lab - BNG Node Startup Script (Final Definitive Version)
# =========================================================================
set -e

# --- 1. Start VPP ---
echo "--> Starting VPP process..."
/usr/bin/vpp -c /etc/vpp/startup.conf &
sleep 5

# --- 2. Configure Global DHCP Relay FIRST ---
KEA4_SERVER="127.0.0.1"
# **THE FIX for DHCPv6**: Use the full, unambiguous IPv6 loopback address. '::1' can be ambiguous to vppctl.
KEA6_SERVER="0:0:0:0:0:0:0:1" 
VPP_RELAY_SRC_IP4="192.101.1.1"
VPP_RELAY_SRC_IP6="2001:db8:101::1"

echo "--> Configuring DHCPv4 and DHCPv6 relay servers..."
vppctl set dhcp proxy server "${KEA4_SERVER}" src-address "${VPP_RELAY_SRC_IP4}"
vppctl set dhcpv6 proxy server "${KEA6_SERVER}" src-address "${VPP_RELAY_SRC_IP6}"

echo "--> Configuring VPP BNG for 4 VLANs..."
# --- 3. Loop Through and Configure Interfaces ---
for i in {0..3}; do
  VLAN_ID=$((101 + i))
  INTERFACE_NAME="eth${i}"
  
  VPP_IPV4_GW="192.${VLAN_ID}.1.1/24"
  VPP_IPV6_GW="2001:db8:${VLAN_ID}::1/64"
  
  echo "    - Configuring ${INTERFACE_NAME} for VLAN ${VLAN_ID}..."
  
  ip link set "${INTERFACE_NAME}" promisc on
  
  vppctl create host-interface name "${INTERFACE_NAME}"
  vppctl set interface state "host-${INTERFACE_NAME}" up
  
  vppctl create sub-interface "host-${INTERFACE_NAME}" "${VLAN_ID}"
  
  SUB_INTERFACE_NAME="host-${INTERFACE_NAME}.${VLAN_ID}"
  
  vppctl set interface ip address "${SUB_INTERFACE_NAME}" "${VPP_IPV4_GW}"
  vppctl set interface ip address "${SUB_INTERFACE_NAME}" "${VPP_IPV6_GW}"
  
  vppctl set interface state "${SUB_INTERFACE_NAME}" up
  
  # **THE FIX for IPv6 RA**: Use the correct 'set interface ip6 nd' syntax.
  # The keyword is 'ra-managed-config-flag' and 'ra-other-config-flag'.
  vppctl set interface ip6 nd "${SUB_INTERFACE_NAME}" ra-managed-config-flag 1
  vppctl set interface ip6 nd "${SUB_INTERFACE_NAME}" ra-other-config-flag 1
  
  # Enable the DHCPv4 relay on this specific sub-interface.
  vppctl set dhcp proxy interface "${SUB_INTERFACE_NAME}"
done

# --- 4. Start Kea DHCP Servers ---
echo "--> VPP BNG configured. Starting Kea DHCP servers..."
kea-dhcp4 -c /etc/kea/kea-dhcp4.conf &
kea-dhcp6 -c /etc/kea/kea-dhcp6.conf &

echo "--- BNG Node is Ready ---"
vppctl show int addr

# --- 5. Keep Container Running ---
tail -f /dev/null