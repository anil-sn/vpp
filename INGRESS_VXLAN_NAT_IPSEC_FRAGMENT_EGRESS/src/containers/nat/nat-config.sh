#!/bin/bash
set -e

echo "--- Configuring NAT Container (Network Address Translation) ---"

# Wait for interfaces to be available
sleep 5

# Create interface from VXLAN container
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 10.1.2.2/24
vppctl set interface state host-eth0 up

# Create interface to IPsec container  
vppctl create host-interface name eth1
vppctl set interface ip address host-eth1 10.1.3.1/24
vppctl set interface state host-eth1 up

# Configure NAT44
vppctl nat44 plugin enable

# Configure interfaces for NAT
vppctl set interface nat44 in host-eth0
vppctl set interface nat44 out host-eth1

# Add NAT44 address pool using the outside interface IP
vppctl nat44 add address 10.1.3.1

# Add static NAT mapping for specific traffic
# Map 10.10.10.10:2055 to 10.1.3.1:2055 for UDP traffic
vppctl nat44 add static mapping udp local 10.10.10.10 2055 external 10.1.3.1 2055

# Set up routing
# Route to previous container (VXLAN)
vppctl ip route add 10.1.1.0/24 via 10.1.2.1

# Route to next container (IPsec)
vppctl ip route add 10.1.4.0/24 via 10.1.3.2

# Route inner network traffic
vppctl ip route add 10.10.10.0/24 via 10.1.2.1

# Enable IP forwarding between interfaces
vppctl set interface feature host-eth0 ip4-unicast-rx on
vppctl set interface feature host-eth1 ip4-unicast-tx on

# Enable packet tracing
vppctl clear trace
vppctl trace add nat44-in2out 50
vppctl trace add nat44-out2in 50
vppctl trace add af-packet-input 50

echo "--- NAT Interfaces ---"
vppctl show interface addr

echo "--- NAT44 Configuration ---"
vppctl show nat44 addresses
vppctl show nat44 static mappings  
vppctl show nat44 interfaces

echo "--- NAT Routes ---"
vppctl show ip fib

echo "--- NAT configuration completed ---"