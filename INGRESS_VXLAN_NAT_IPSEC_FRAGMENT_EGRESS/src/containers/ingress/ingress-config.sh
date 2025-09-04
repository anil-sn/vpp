#!/bin/bash
set -e

echo "--- Configuring INGRESS Container (Simplified) ---"

# Create host interfaces for inter-container communication
vppctl set interface managed eth0
vppctl set interface ip address eth0 172.20.0.10/24
vppctl set interface state eth0 up

vppctl set interface managed eth1
vppctl set interface ip address eth1 172.20.1.10/24
vppctl set interface state eth1 up



# Set up basic routing
vppctl ip route add 172.20.2.0/24 via 172.20.1.20
vppctl ip route add 0.0.0.0/0 via 172.20.0.1

echo "--- INGRESS Interfaces (Simplified) ---"
vppctl show interface addr

echo "--- INGRESS Routes (Simplified) ---"
vppctl show ip fib

echo "--- INGRESS Simplified configuration completed ---"