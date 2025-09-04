#!/bin/bash
set -e

echo "--- Configuring VXLAN Container (Decapsulation) ---"

# Wait for interfaces to be available
sleep 5

# Create interface from INGRESS container
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 10.1.1.2/24
vppctl set interface state host-eth0 up

# Create interface to NAT container
vppctl create host-interface name eth1
vppctl set interface ip address host-eth1 10.1.2.1/24
vppctl set interface state host-eth1 up

# Create VXLAN tunnel for decapsulation
# This will handle VXLAN packets coming from the underlay network
vppctl create vxlan tunnel src 10.1.1.2 dst 10.1.1.1 vni 100 decap-next l2
vppctl set interface state vxlan_tunnel0 up

# Create bridge domain for VXLAN decapsulation
vppctl create bridge-domain 1 learn 1 forward 1 uu-flood 1 flood 1 arp-term 0
vppctl set interface l2 bridge vxlan_tunnel0 1
vppctl set interface l2 bridge host-eth1 1

# Set up IP routing for decapsulated packets
# Route inner packets (10.10.10.0/24) to NAT container
vppctl ip route add 10.10.10.0/24 via 10.1.2.2

# Route return traffic
vppctl ip route add 10.1.3.0/24 via 10.1.2.2

# Enable IP forwarding between interfaces
vppctl set interface feature host-eth0 ip4-unicast-rx on
vppctl set interface feature host-eth1 ip4-unicast-tx on

# Enable VXLAN decapsulation
vppctl set interface feature host-eth0 vxlan4-input on

# Enable packet tracing
vppctl clear trace
vppctl trace add vxlan4-input 50
vppctl trace add af-packet-input 50

echo "--- VXLAN Interfaces ---"
vppctl show interface addr

echo "--- VXLAN Bridge Domains ---"
vppctl show bridge-domain

echo "--- VXLAN Tunnels ---"
vppctl show vxlan tunnel

echo "--- VXLAN Routes ---"
vppctl show ip fib

echo "--- VXLAN configuration completed ---"