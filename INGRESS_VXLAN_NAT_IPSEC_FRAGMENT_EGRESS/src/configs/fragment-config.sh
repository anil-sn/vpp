#!/bin/bash
set -e

echo "--- Configuring FRAGMENT Container (IP Fragmentation) ---"

# Create interfaces
vppctl create host-interface name fragment-in
vppctl set interface ip address host-fragment-in 10.1.4.2/24
vppctl set interface state host-fragment-in up

vppctl create host-interface name fragment-out
vppctl set interface ip address host-fragment-out 192.168.1.4/24
vppctl set interface state host-fragment-out up

# Set MTU to trigger fragmentation
vppctl set interface mtu 1400 host-fragment-out

# Routing to GCP
vppctl ip route add 192.168.1.3/32 via host-fragment-out
vppctl ip route add 10.0.3.0/24 via host-fragment-out
vppctl ip route add 0.0.0.0/0 via 192.168.1.1

# Enable tracing
vppctl clear trace
vppctl trace add ip4-frag 10

echo "--- FRAGMENT configuration completed ---"