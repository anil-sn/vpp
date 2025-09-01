#!/bin/bash
# aws-config.sh
#
# This script configures the VPP instance on the AWS node. It is executed
# inside the AWS container by the setup.sh script.

# Exit immediately if any command fails.
set -e

echo "--- Configuring AWS ---"

# --- 1. VPP -> Linux Kernel Interface (TAP) ---
# Create a TAP interface, which acts as a virtual network adapter.
# VPP will expose this interface to the container's Linux kernel.
vppctl create tap id 0 host-if-name vpp-linux
# CRITICAL MTU CONFIGURATION:
# An interface MUST be brought DOWN before changing its physical properties.
# This 'set interface mtu packet' command allocates large hardware-level
# packet buffers, which is the key to receiving jumbo frames from the kernel.
vppctl set interface state tap0 down
vppctl set interface mtu packet 9000 tap0
# Assign the IP address that will serve as the gateway for the Linux kernel.
vppctl set interface ip address tap0 10.0.1.2/24
vppctl set interface state tap0 up

# --- 2. VPP -> Host/Underlay Interface (af_packet) ---
# Create a VPP host-interface that binds to the 'aws-phy' veth pair,
# connecting VPP to the host's Linux bridge.
vppctl create host-interface name aws-phy
# Repeat the DOWN -> CONFIGURE -> UP sequence for the physical MTU.
vppctl set interface state host-aws-phy down
vppctl set interface mtu packet 9000 host-aws-phy
# Assign the underlay IP address for the AWS side.
vppctl set interface ip address host-aws-phy 192.168.1.2/24
vppctl set interface state host-aws-phy up

# --- 3. IPsec Security Association (SA) Configuration ---
# An SA is a one-way security contract. We need two SAs for a bidirectional tunnel.
# This SA defines the parameters for OUTgoing traffic (AWS -> GCP).
# It uses Security Parameter Index (SPI) 1000.
vppctl ipsec sa add 1000 spi 1000 esp crypto-alg aes-gcm-128 crypto-key 4a506a794f574265564551694d653768
# This SA defines the parameters for INcoming traffic (GCP -> AWS).
# It uses SPI 2000.
vppctl ipsec sa add 2000 spi 2000 esp crypto-alg aes-gcm-128 crypto-key 4a506a794f574265564551694d653768

# --- 4. Tunnel Interface Configuration ---
# Create a virtual IPIP tunnel interface. This provides a logical interface
# that we can apply the IPsec policy to and route traffic through.
vppctl create ipip tunnel src 192.168.1.2 dst 192.168.1.3
# Protect the tunnel. This command binds the SAs to the tunnel interface.
# Packets routed out of ipip0 will use SA 1000 (sa-out).
# Packets arriving on the underlay destined for this tunnel must match SA 2000 (sa-in).
vppctl ipsec tunnel protect ipip0 sa-in 2000 sa-out 1000
# Set a small MTU on the tunnel interface. This forces VPP to fragment any large
# packets before they are encrypted, allowing us to test fragmentation/reassembly.
vppctl set interface mtu packet 1400 ipip0
# Assign the tunnel to the default IP routing table (table 0). This is essential
# for VPP to treat it as a proper L3 interface for routing decrypted packets.
vppctl set interface ip table ipip0 0
# Assign a link-local IP. While not used for routing, this helps ensure the
# interface is fully initialized as an L3 entity in VPP.
vppctl set interface ip address ipip0 169.254.1.1/30
vppctl set interface state ipip0 up

# --- 5. VPP Routing Logic ---
# Route traffic for the remote GCP private network (10.0.2.0/24) INTO the tunnel.
vppctl ip route add 10.0.2.0/24 via ipip0
# Route traffic for the local AWS private network (10.0.1.0/24) OUT to the kernel.
# This tells VPP where to send packets after they have been decrypted.
vppctl ip route add 10.0.1.0/24 via tap0

# --- 6. Linux Kernel Networking Configuration ---
# These commands are run from within the VPP configuration script, but they
# affect the container's Linux kernel, not VPP itself.
# Assign an IP address to the Linux side of the TAP interface.
ip addr add 10.0.1.1/24 dev vpp-linux
ip link set vpp-linux up
# Set a jumbo MTU on the Linux side to match the VPP side.
ip link set dev vpp-linux mtu 9000
# Add a route in the Linux kernel to send traffic for the GCP network to VPP.
ip route add 10.0.2.0/24 via 10.0.1.2

echo "--- AWS configuration applied. ---"