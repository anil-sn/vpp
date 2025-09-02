#!/bin/bash
# gcp-config.sh
#
# This script configures the VPP instance on the GCP node. It acts as a
# standard IPsec endpoint to receive the forwarded traffic.

# Exit immediately if any command fails.
set -e

echo "--- Configuring GCP ---"

# --- 1. VPP -> Linux Kernel Interface (TAP) ---
# Create a TAP interface to connect VPP to this container's Linux kernel.
vppctl create tap id 0 host-if-name vpp-linux
# Assign the IP address that will serve as the gateway for the Linux kernel.
vppctl set interface ip address tap0 10.0.2.2/24
vppctl set interface state tap0 up

# --- 2. VPP -> Host/Underlay Interface (af_packet) ---
# Create a VPP host-interface that binds to the 'gcp-phy' veth pair.
vppctl create host-interface name gcp-phy
# Assign the underlay IP address for the GCP side.
vppctl set interface ip address host-gcp-phy 192.168.1.3/24
vppctl set interface state host-gcp-phy up

# --- 3. IPsec Security Association (SA) Configuration ---
# The SA configuration is a mirror of the AWS side.
# This SA is for INcoming traffic (AWS -> GCP). It must match AWS's OUTbound SA.
vppctl ipsec sa add 1000 spi 1000 esp crypto-alg aes-gcm-128 crypto-key 4a506a794f574265564551694d653768
# This SA is for OUTgoing traffic (GCP -> AWS). It must match AWS's INbound SA.
vppctl ipsec sa add 2000 spi 2000 esp crypto-alg aes-gcm-128 crypto-key 4a506a794f574265564551694d653768

# --- 4. Tunnel Interface Configuration ---
# Create the IPIP tunnel interface with source and destination IPs swapped.
vppctl create ipip tunnel src 192.168.1.3 dst 192.168.1.2
# Protect the tunnel, ensuring the sa-in and sa-out values are the mirror of the AWS side.
vppctl ipsec tunnel protect ipip0 sa-in 1000 sa-out 2000
# Assign the tunnel to the default IP routing table.
vppctl set interface ip table ipip0 0
vppctl set interface state ipip0 up

# --- 5. VPP Routing Logic ---
# Route traffic for the remote AWS private network (10.0.1.0/24) INTO the tunnel.
vppctl ip route add 10.0.1.0/24 via ipip0
# Route decrypted traffic for the local GCP private network (10.0.2.0/24) OUT to the kernel.
vppctl ip route add 10.0.2.0/24 via tap0

# --- 6. Linux Kernel Networking Configuration ---
# Assign an IP address to the Linux side of the TAP interface.
ip addr add 10.0.2.1/24 dev vpp-linux
ip link set vpp-linux up
# Add a route in the Linux kernel to send traffic for the AWS network to VPP.
ip route add 10.0.1.0/24 via 10.0.2.2

echo "--- GCP configuration applied. ---"