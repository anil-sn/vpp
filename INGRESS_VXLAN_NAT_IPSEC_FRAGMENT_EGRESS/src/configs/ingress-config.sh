#!/bin/bash
set -e

echo "--- Configuring INGRESS Container (VXLAN Reception) ---"

# Create host interface for receiving traffic
vppctl create host-interface name ingress-phy
vppctl set interface ip address host-ingress-phy 192.168.1.2/24
vppctl set interface state host-ingress-phy up

# Simple forwarding configuration
# Forward incoming VXLAN packets to the next container in chain
vppctl ip route add 0.0.0.0/0 via 192.168.1.1

# Enable packet tracing
vppctl clear trace
vppctl trace add af-packet-input 10

echo "--- INGRESS configuration completed ---"