#!/bin/bash
set -e

echo "--- Configuring VXLAN Container ---"

# Create host interfaces
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 172.20.1.20/24  
vppctl set interface state host-eth0 up

vppctl create host-interface name eth1
vppctl set interface ip address host-eth1 172.20.2.10/24
vppctl set interface state host-eth1 up

# Create VXLAN tunnel for L3 decapsulation
vppctl create vxlan tunnel src 172.20.1.20 dst 172.20.1.10 vni 100
vppctl set interface state vxlan_tunnel0 up

# Since we're doing L3 processing, route the decapsulated packets
# The VXLAN tunnel will decapsulate and forward to the routing table
vppctl ip route add 10.10.10.0/24 via 172.20.2.20 host-eth1

echo "--- VXLAN configuration completed ---"  
vppctl show interface addr
vppctl show vxlan tunnel  
vppctl show ip fib