#!/bin/bash
set -e

echo "--- Configuring NAT Container (Address Translation) ---"

# Create interfaces
vppctl create host-interface name nat-in
vppctl set interface ip address host-nat-in 10.1.2.2/24
vppctl set interface state host-nat-in up

vppctl create host-interface name nat-out
vppctl set interface ip address host-nat-out 10.1.3.1/24
vppctl set interface state host-nat-out up

# Configure NAT44
vppctl nat44 plugin enable
vppctl set interface nat44 in host-nat-in
vppctl set interface nat44 out host-nat-out

# Static mapping: 10.10.10.10:2055 → 10.0.3.1:2055
vppctl nat44 add static mapping udp local 10.10.10.10 2055 external 10.0.3.1 2055

# Routing
vppctl ip route add 10.10.10.0/24 via host-nat-in
vppctl ip route add 10.0.3.0/24 via host-nat-out
vppctl ip route add 10.1.3.0/24 via host-nat-out

# Enable tracing
vppctl clear trace
vppctl trace add nat44-in2out 10

echo "--- NAT configuration completed ---"