#!/bin/bash
set -e

echo "--- Configuring INGRESS Container (Fixed) ---"

# Create host interfaces for inter-container communication
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 172.20.0.10/24
vppctl set interface state host-eth0 up

vppctl create host-interface name eth1
vppctl set interface ip address host-eth1 172.20.1.10/24
vppctl set interface state host-eth1 up

# Set up basic routing
vppctl ip route add 172.20.2.0/24 via 172.20.1.20
vppctl ip route add 0.0.0.0/0 via 172.20.0.1

echo "--- INGRESS Interfaces (Fixed) ---"
vppctl show interface addr

echo "--- INGRESS Routes (Fixed) ---"
vppctl show ip fib

echo "--- INGRESS Fixed configuration completed ---"