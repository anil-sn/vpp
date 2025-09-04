#!/bin/bash
set -e

echo "--- Configuring IPsec Container (ESP Encryption) ---"

# Wait for interfaces to be available
sleep 5

# Create interface from NAT container
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 10.1.3.2/24
vppctl set interface state host-eth0 up

# Create interface to Fragment container
vppctl create host-interface name eth1
vppctl set interface ip address host-eth1 10.1.4.1/24
vppctl set interface state host-eth1 up

# Configure IPsec Security Associations (SAs)
# Outbound SA (encrypt)
vppctl ipsec sa add 1000 spi 1000 esp \
    crypto-alg aes-gcm-128 \
    crypto-key 4a506a794f574265564551694d653768

# Inbound SA (decrypt) 
vppctl ipsec sa add 2000 spi 2000 esp \
    crypto-alg aes-gcm-128 \
    crypto-key 4a506a794f574265564551694d653768

# Create IPIP tunnel with IPsec protection
vppctl create ipip tunnel src 10.1.3.2 dst 10.1.4.2
vppctl ipsec tunnel protect ipip0 sa-in 2000 sa-out 1000
vppctl set interface state ipip0 up

# Set IP address on tunnel interface
vppctl set interface ip address ipip0 10.100.100.1/30

# Set up routing
# Route to previous container (NAT)
vppctl ip route add 10.1.2.0/24 via 10.1.3.1

# Route to next container (Fragment) via tunnel
vppctl ip route add 10.1.5.0/24 via ipip0

# Route specific traffic through tunnel
vppctl ip route add 192.168.10.0/24 via ipip0

# Enable IP forwarding between interfaces
vppctl set interface feature host-eth0 ip4-unicast-rx on
vppctl set interface feature host-eth1 ip4-unicast-tx on

# Enable IPsec processing
vppctl set interface feature host-eth0 ipsec4-input on
vppctl set interface feature ipip0 ipsec4-output on

# Enable packet tracing
vppctl clear trace
vppctl trace add ipsec4-output 50
vppctl trace add ipsec4-input 50
vppctl trace add af-packet-input 50

echo "--- IPsec Interfaces ---"
vppctl show interface addr

echo "--- IPsec SAs ---"
vppctl show ipsec sa

echo "--- IPsec Tunnels ---"
vppctl show ipsec tunnel

echo "--- IPsec Routes ---"
vppctl show ip fib

echo "--- IPsec configuration completed ---"