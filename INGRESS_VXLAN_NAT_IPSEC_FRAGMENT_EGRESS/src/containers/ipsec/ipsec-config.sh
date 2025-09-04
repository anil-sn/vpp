#!/bin/bash
set -e

echo "--- Configuring IPsec Container (Simplified) ---"

# Create interface from NAT container
vppctl set interface managed eth0
vppctl set interface ip address eth0 172.20.3.20/24
vppctl set interface state eth0 up

# Create interface to Fragment container
vppctl set interface managed eth1
vppctl set interface ip address eth1 172.20.4.10/24
vppctl set interface state eth1 up

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
vppctl create ipip tunnel src 172.20.3.20 dst 172.20.4.20
vppctl ipsec tunnel protect ipip0 sa-in 2000 sa-out 1000
vppctl set interface state ipip0 up



# Set IP address on tunnel interface
vppctl set interface ip address ipip0 10.100.100.1/30

# Set up routing
# Route to previous container (NAT)
vppctl ip route add 172.20.2.0/24 via 172.20.3.10

# Route to next container (Fragment) via tunnel
vppctl ip route add 172.20.5.0/24 via ipip0

# Route specific traffic through tunnel
vppctl ip route add 172.20.0.0/24 via ipip0

echo "--- IPsec Interfaces (Simplified) ---"
vppctl show interface addr

echo "--- IPsec SAs (Simplified) ---"
vppctl show ipsec sa

echo "--- IPsec Tunnels (Simplified) ---"
vppctl show ipsec tunnel

echo "--- IPsec Routes (Simplified) ---"
vppctl show ip fib

echo "--- IPsec Simplified configuration completed ---"
