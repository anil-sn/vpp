#!/bin/bash
set -e

echo "--- Configuring VXLAN Container (Fixed) ---"

# Create host interfaces for inter-container communication
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 172.20.1.20/24
vppctl set interface state host-eth0 up

vppctl create host-interface name eth1
vppctl set interface ip address host-eth1 172.20.2.10/24
vppctl set interface state host-eth1 up

# Create VXLAN tunnel for decapsulation
vppctl create vxlan tunnel src 172.20.1.20 dst 172.20.1.10 vni 100 decap-next l2
vppctl set interface state vxlan_tunnel0 up

# Create bridge domain for VXLAN decapsulation
vppctl create bridge-domain 1 learn 1 forward 1 uu-flood 1 flood 1 arp-term 0
vppctl set interface l2 bridge vxlan_tunnel0 1
vppctl set interface l2 bridge host-eth1 1

# Set up IP routing for decapsulated packets
vppctl ip route add 10.10.10.0/24 via 172.20.2.20
vppctl ip route add 172.20.3.0/24 via 172.20.2.20

echo "--- VXLAN Interfaces (Fixed) ---"
vppctl show interface addr

echo "--- VXLAN Bridge Domains (Fixed) ---"
vppctl show bridge-domain

echo "--- VXLAN Tunnels (Fixed) ---"
vppctl show vxlan tunnel

echo "--- VXLAN Routes (Fixed) ---"
vppctl show ip fib

echo "--- VXLAN Fixed configuration completed ---"