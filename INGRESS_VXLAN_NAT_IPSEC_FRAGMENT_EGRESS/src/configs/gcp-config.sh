#!/bin/bash
set -e

echo "--- Configuring GCP Container (Destination Endpoint) ---"

# Create interface
vppctl create host-interface name gcp-phy
vppctl set interface ip address host-gcp-phy 192.168.1.3/24
vppctl set interface state host-gcp-phy up

# Create TAP interface for Linux integration
vppctl create tap id 0
vppctl set interface ip address tap0 10.0.2.2/24
vppctl set interface state tap0 up

# Routing
vppctl ip route add 0.0.0.0/0 via 192.168.1.1
vppctl ip route add 10.0.3.0/24 via tap0

# Enable tracing
vppctl clear trace
vppctl trace add af-packet-input 10

echo "--- GCP configuration completed ---"