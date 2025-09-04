#!/bin/bash
set -e

echo "--- Configuring FRAGMENT Container (Simplified) ---
"

# Create interface from IPsec container
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 172.20.4.20/24
vppctl set interface state host-eth0 up

# Create interface to underlay network (GCP)
vppctl create host-interface name eth1
vppctl set interface ip address host-eth1 172.20.5.10/24
vppctl set interface state host-eth1 up

# Set MTU on output interface to trigger fragmentation
vppctl set interface mtu packet 1400 host-eth1



# Set up routing
# Route to previous container (IPsec)
vppctl ip route add 172.20.3.0/24 via 172.20.4.10

# Route to GCP destination
vppctl ip route add 172.20.5.20/32 via 172.20.5.1

# Route all other traffic to underlay gateway
vppctl ip route add 0.0.0.0/0 via 172.20.5.1

echo "--- Fragment Interfaces (Simplified) ---
"
vppctl show interface addr

echo "--- Fragment MTU Settings (Simplified) ---
"
vppctl show interface host-eth1 features

echo "--- Fragment Routes (Simplified) ---
"
vppctl show ip fib

echo "--- FRAGMENT Simplified configuration completed ---
"