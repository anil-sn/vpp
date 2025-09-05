#!/bin/bash
set -e

echo "--- Configuring NAT Container ---"

# Create interfaces
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 172.20.2.20/24
vppctl set interface state host-eth0 up

vppctl create host-interface name eth1  
vppctl set interface ip address host-eth1 172.20.3.10/24
vppctl set interface state host-eth1 up

# Enable NAT44 plugin
vppctl nat44 plugin enable sessions 1024

# Configure NAT interfaces
vppctl set interface nat44 in host-eth0
vppctl set interface nat44 out host-eth1

# Add address pool
vppctl nat44 add address 172.20.3.10

# Add static mapping for the test traffic
vppctl nat44 add static mapping udp local 10.10.10.10 2055 external 172.20.3.10 2055

# Set up routing
vppctl ip route add 10.10.10.0/24 via 172.20.2.10 host-eth0
vppctl ip route add 172.20.4.0/24 via 172.20.3.20 host-eth1

echo "--- NAT configuration completed ---"
vppctl show interface addr
vppctl show nat44 addresses
vppctl show nat44 static mappings
vppctl show ip fib