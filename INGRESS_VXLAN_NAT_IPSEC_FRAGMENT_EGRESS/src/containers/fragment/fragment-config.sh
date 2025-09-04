#!/bin/bash
set -e

echo "--- Configuring FRAGMENT Container (IP Fragmentation) ---"

# Wait for interfaces to be available
sleep 5

# Create interface from IPsec container
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 10.1.4.2/24
vppctl set interface state host-eth0 up

# Create interface to underlay network (GCP)
vppctl create host-interface name eth1
vppctl set interface ip address host-eth1 192.168.10.4/24
vppctl set interface state host-eth1 up

# Set MTU on output interface to trigger fragmentation
vppctl set interface mtu packet 1400 host-eth1

# Enable IP fragmentation on the output interface
vppctl set interface feature host-eth1 ip4-output on

# Set up routing
# Route to previous container (IPsec)
vppctl ip route add 10.1.3.0/24 via 10.1.4.1

# Route to GCP destination
vppctl ip route add 192.168.10.3/32 via 192.168.10.1

# Route all other traffic to underlay gateway
vppctl ip route add 0.0.0.0/0 via 192.168.10.1

# Enable IP forwarding between interfaces
vppctl set interface feature host-eth0 ip4-unicast-rx on
vppctl set interface feature host-eth1 ip4-unicast-tx on

# Enable packet tracing
vppctl clear trace
vppctl trace add ip4-frag 50
vppctl trace add af-packet-input 50
vppctl trace add ip4-rewrite 50

echo "--- Fragment Interfaces ---"
vppctl show interface addr

echo "--- Fragment MTU Settings ---"
vppctl show interface host-eth1 features

echo "--- Fragment Routes ---"
vppctl show ip fib

echo "--- FRAGMENT configuration completed ---"