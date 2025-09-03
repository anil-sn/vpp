#!/bin/bash
set -e

echo "--- Configuring IPsec Container (ESP Encryption) ---"

# Create interfaces
vppctl create host-interface name ipsec-in
vppctl set interface ip address host-ipsec-in 10.1.3.2/24
vppctl set interface state host-ipsec-in up

vppctl create host-interface name ipsec-out
vppctl set interface ip address host-ipsec-out 10.1.4.1/24
vppctl set interface state host-ipsec-out up

# Configure IPsec SAs
vppctl ipsec sa add 1000 spi 1000 esp crypto-alg aes-gcm-128 crypto-key 4a506a794f574265564551694d653768
vppctl ipsec sa add 2000 spi 2000 esp crypto-alg aes-gcm-128 crypto-key 4a506a794f574265564551694d653768

# Create IPIP tunnel with IPsec protection
vppctl create ipip tunnel src 10.1.3.2 dst 10.1.4.2
vppctl ipsec tunnel protect ipip0 sa-in 2000 sa-out 1000
vppctl set interface state ipip0 up

# Routing
vppctl ip route add 10.0.3.0/24 via ipip0
vppctl ip route add 10.1.4.0/24 via host-ipsec-out

# Enable tracing
vppctl clear trace
vppctl trace add ipsec4-output 10

echo "--- IPsec configuration completed ---"