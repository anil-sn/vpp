#!/bin/bash
set -e

echo "--- Configuring NAT Container (Simplified) ---
"

# Create interface from VXLAN container
vppctl set interface managed eth0
vppctl set interface ip address eth0 172.20.2.20/24
vppctl set interface state eth0 up

# Create interface to IPsec container  
vppctl set interface managed eth1
vppctl set interface ip address eth1 172.20.3.10/24
vppctl set interface state eth1 up



# Configure NAT44
vppctl nat44 plugin enable

# Configure interfaces for NAT
vppctl set interface nat44 in host-eth0
vppctl set interface nat44 out host-eth1

# Add NAT44 address pool using the outside interface IP
vppctl nat44 add address 172.20.3.10

# Add static NAT mapping for specific traffic
# Map 10.10.10.10:2055 to 172.20.3.10:2055 for UDP traffic
vppctl nat44 add static mapping udp local 10.10.10.10 2055 external 172.20.3.10 2055

# Set up routing
# Route to previous container (VXLAN)
vppctl ip route add 172.20.1.0/24 via 172.20.2.10

# Route to next container (IPsec)
vppctl ip route add 172.20.4.0/24 via 172.20.3.20

# Route inner network traffic
vppctl ip route add 10.10.10.0/24 via 172.20.2.10

echo "--- NAT Interfaces (Simplified) ---
"
vppctl show interface addr

echo "--- NAT44 Configuration (Simplified) ---
"
vppctl show nat44 addresses
vppctl show nat44 static mappings  
vppctl show nat44 interfaces

echo "--- NAT Routes (Simplified) ---
"
vppctl show ip fib

echo "--- NAT Simplified configuration completed ---
"