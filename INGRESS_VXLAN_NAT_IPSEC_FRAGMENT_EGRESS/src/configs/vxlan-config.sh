#!/bin/bash
set -e

echo "--- Configuring VXLAN Container (Decapsulation) ---"

# Create interfaces
vppctl create host-interface name vxlan-in
vppctl set interface ip address host-vxlan-in 10.1.1.2/24
vppctl set interface state host-vxlan-in up

vppctl create host-interface name vxlan-out
vppctl set interface ip address host-vxlan-out 10.1.2.1/24
vppctl set interface state host-vxlan-out up

# Create VXLAN tunnel for decapsulation
vppctl create vxlan tunnel src 10.1.1.2 dst 10.1.1.1 vni 100
vppctl set interface ip address vxlan_tunnel0 10.99.99.1/24
vppctl set interface state vxlan_tunnel0 up

# Route inner packets to NAT container
vppctl ip route add 10.10.10.0/24 via vxlan_tunnel0
vppctl ip route add 10.1.2.0/24 via host-vxlan-out

# Enable tracing
vppctl clear trace
vppctl trace add vxlan4-input 10

echo "--- VXLAN configuration completed ---"