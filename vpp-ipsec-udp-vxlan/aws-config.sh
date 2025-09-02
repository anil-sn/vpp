#!/bin/bash
# aws-config.sh (FINAL WORKING VERSION - Simplified)

set -e

echo "--- Configuring AWS VPP (VXLAN -> NAT -> IPsec) ---"

# --- Block 1: Interfaces and IPsec ---
vppctl create host-interface name aws-phy
vppctl set interface ip address host-aws-phy 192.168.1.2/24
vppctl set interface state host-aws-phy up

vppctl ipsec sa add 1000 spi 1000 esp crypto-alg aes-gcm-128 crypto-key 4a506a794f574265564551694d653768
vppctl ipsec sa add 2000 spi 2000 esp crypto-alg aes-gcm-128 crypto-key 4a506a794f574265564551694d653768
vppctl create ipip tunnel src 192.168.1.2 dst 192.168.1.3
vppctl ipsec tunnel protect ipip0 sa-in 2000 sa-out 1000
vppctl set interface ip table ipip0 0
vppctl set interface state ipip0 up

# --- Block 2: VXLAN Tunnel ---
vppctl create vxlan tunnel src 192.168.1.2 dst 0.0.0.0 vni 100
vppctl set interface ip table vxlan_tunnel0 0
vppctl set interface state vxlan_tunnel0 up

# --- Block 3: The Direct NAT Configuration ---

# Enable the NAT44 feature globally. This is YOUR key discovery.
vppctl nat44 plugin enable

# Directly apply NAT to the VXLAN (in) and IPsec (out) interfaces.
vppctl set interface nat44 in vxlan_tunnel0 out ipip0

# Add the static mapping rule.
vppctl nat44 add static mapping udp local 10.10.10.10 2055 external 10.0.2.1 2055

# --- Block 4: Routing ---
# This single route sends the NAT'd packet into the IPsec tunnel.
vppctl ip route add 10.0.2.0/24 via ipip0

echo "--- AWS VPP configuration applied SUCCESSFULLY. ---"