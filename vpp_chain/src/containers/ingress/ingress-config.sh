#!/bin/bash
set -e

echo "--- Configuring INGRESS Container ---"

# Create host interfaces
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 172.20.0.10/24
vppctl set interface state host-eth0 up

vppctl create host-interface name eth1  
vppctl set interface ip address host-eth1 172.20.1.10/24
vppctl set interface state host-eth1 up

# Enable IP forwarding
vppctl set interface unnumbered host-eth0 use host-eth1
vppctl set interface unnumbered host-eth1 use host-eth0

# Set up routing to forward VXLAN traffic to next container
vppctl ip route add 172.20.1.20/32 via 172.20.1.20 host-eth1
vppctl ip route add 172.20.2.0/24 via 172.20.1.20 host-eth1

echo "--- INGRESS configuration completed ---"
vppctl show interface addr
vppctl show ip fib