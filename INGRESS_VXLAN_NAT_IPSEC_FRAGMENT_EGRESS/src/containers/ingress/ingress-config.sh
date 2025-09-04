#!/bin/bash
set -e

echo "--- Configuring INGRESS Container (VXLAN Reception) ---"

# Wait for interfaces to be available
sleep 5

# Create host interfaces for inter-container communication
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 192.168.10.2/24
vppctl set interface state host-eth0 up

# Create interface to next container (VXLAN)
vppctl create host-interface name eth1
vppctl set interface ip address host-eth1 10.1.1.1/24
vppctl set interface state host-eth1 up

# Set up basic routing
# Route traffic to VXLAN container
vppctl ip route add 10.1.2.0/24 via 10.1.1.2
vppctl ip route add 0.0.0.0/0 via 192.168.10.1

# Configure VXLAN listener for incoming traffic
vppctl set interface ip address host-eth0 192.168.10.2/24

# Enable IP forwarding
vppctl set interface feature host-eth0 ip4-unicast-rx on
vppctl set interface feature host-eth1 ip4-unicast-tx on

# Enable packet tracing
vppctl clear trace
vppctl trace add af-packet-input 50

echo "--- INGRESS Interfaces ---"
vppctl show interface addr

echo "--- INGRESS Routes ---"
vppctl show ip fib

echo "--- INGRESS configuration completed ---"