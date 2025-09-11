#!/bin/bash

# AWS VXLAN Decapsulation Configuration for Traffic Mirroring
# Handles Layer 2 MAC address rewriting to solve AWS ENI source MAC enforcement

# Get container configuration from environment
VXLAN_SRC_IP=${VXLAN_SRC_IP:-"10.10.0.10"}
VXLAN_DST_IP=${VXLAN_DST_IP:-"10.10.0.1"} 
VXLAN_VNI=${VXLAN_VNI:-"100"}
HOST_ETH0_MAC=$(cat /sys/class/net/eth0/address)
HOST_ETH1_MAC=$(cat /sys/class/net/eth1/address)

cat > /tmp/vpp-aws-vxlan.conf << EOF
# AWS Traffic Mirror VXLAN Decapsulation Configuration

# Enable required plugins for AWS traffic processing
plugins {
    plugin af_packet_plugin.so { enable }
    plugin vxlan_plugin.so { enable }
    plugin nat_plugin.so { enable }
    plugin mactime_plugin.so { enable }
}

# Create host interfaces with optimized settings for AWS
create host-interface name eth0 hw-addr $HOST_ETH0_MAC
create host-interface name eth1 hw-addr $HOST_ETH1_MAC

# Set interfaces to up state
set interface state host-eth0 up
set interface state host-eth1 up

# Configure interface IP addresses
set interface ip address host-eth0 $VXLAN_SRC_IP/24  
set interface ip address host-eth1 10.11.0.10/24

# Create VXLAN tunnel for AWS Traffic Mirroring decapsulation
create vxlan tunnel src $VXLAN_SRC_IP dst $VXLAN_DST_IP vni $VXLAN_VNI decap-next l2

# Set VXLAN tunnel interface up
set interface state vxlan_tunnel0 up

# Configure MTU for VXLAN tunnel to handle DF bit packets
# AWS adds 50 bytes VXLAN overhead, so reduce MTU accordingly
set interface mtu packet 1450 vxlan_tunnel0

# Configure DF bit handling - clear DF bit on VXLAN encapsulated packets
set interface feature vxlan_tunnel0 ip4-reassembly arc ip4-unicast

# Create bridge domain for Layer 2 processing with MAC learning disabled
# This is crucial for AWS - we don't want to learn original MACs
create bridge-domain 1 learn 0 forward 1 uu-flood 1 flood 1 arp-term 0

# Add VXLAN tunnel to bridge domain
set interface l2 bridge vxlan_tunnel0 1

# Create loopback interface for MAC rewriting
create loopback interface

# Set loopback interface up  
set interface state loop0 up
set interface ip address loop0 10.255.255.1/32

# Add loopback to bridge domain
set interface l2 bridge loop0 1

# Create TAP interface for processed packets
create tap id 0 host-if-name vpp-aws-tap0 host-bridge br0

# Set TAP interface up
set interface state tap0 up
set interface ip address tap0 10.200.1.1/24

# Configure MAC address rewriting for AWS ENI compliance
# This solves the Layer 2 forwarding problem described
create classify table mask l2.dst next-node l2-input-classify
create classify session table-index 0 match l2.dst action set-ip4-fib-id 0

# Set up L3 forwarding after MAC rewrite
ip route add 0.0.0.0/0 via 10.11.0.1 host-eth1

# Enable L3 processing on bridge domain interface
create sub-interface loop0 1
set interface state loop0.1 up  
set interface ip address loop0.1 10.11.0.5/24
set interface l2 bridge loop0.1 1 bvi

# Configure DF bit handling for AWS Traffic Mirror packets
# Clear DF bit on packets that would exceed MTU after decapsulation
ip reassembly enable-disable ipv4 on
ip reassembly max-reassemblies 1024
ip reassembly max-reassembly-length 30000
ip reassembly expire-walk-interval 10000

# Handle DF bit packets that cannot be fragmented for UDP traffic
# For UDP with DF=1, we need to either drop or clear the DF bit
create packet-drop-reason aws-df-bit-oversized "UDP packet with DF bit exceeds MTU"

# Configure DF bit clearing for oversized UDP packets
# This allows UDP packets >MTU to be fragmented by clearing DF bit
ip punt add reason aws-df-bit-oversized interface host-eth1

# Configure packet punting for foreign MAC addresses to Linux stack
set punt unknown-l3-protocol ip4 punt-to-host
set punt unknown-l3-protocol ip6 punt-to-host

# Set interface features for MAC rewriting and DF bit handling
set interface feature host-eth1 l2-input-classify arc l2-input
set interface feature host-eth0 ip4-reassembly arc ip4-unicast

# Configure ARP for proper Layer 3 forwarding
set ip arp static host-eth1 10.11.0.1 $HOST_ETH1_MAC
set ip arp static loop0.1 10.11.0.1 $HOST_ETH1_MAC

# Enable trace for debugging AWS traffic flow
trace add af-packet-input 50
trace add vxlan4-input 50
trace add l2-input 50
trace add l2-bridge 50

# Set interface to polling mode for high performance
set interface rx-mode host-eth0 polling
set interface rx-mode host-eth1 polling

# Configure buffer allocation for AWS workloads
set logging class vxlan level info
set logging class l2 level info

EOF

echo "Starting VPP with AWS VXLAN configuration..."
vpp -c /vpp-common/startup.conf &
sleep 5

echo "Applying AWS VXLAN decapsulation configuration..."
vppctl exec /tmp/vpp-aws-vxlan.conf

# Create bridge for processed packets on Linux side
brctl addbr br0 2>/dev/null || true
brctl setfd br0 0 2>/dev/null || true  
brctl stp br0 off 2>/dev/null || true
ip link set br0 up

# Configure iptables for source IP preservation
iptables -t nat -F
iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE

# Set up forwarding for processed packets
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter
echo 0 > /proc/sys/net/ipv4/conf/eth0/rp_filter  
echo 0 > /proc/sys/net/ipv4/conf/eth1/rp_filter

# Monitor AWS traffic processing
echo "AWS VXLAN decapsulation configured. Monitoring traffic..."
while true; do
    echo "$(date): VXLAN tunnel stats:"
    vppctl show vxlan tunnel | grep -E "(rx|tx) packets"
    echo "$(date): Bridge domain stats:" 
    vppctl show bridge-domain 1 detail | grep -E "rx|tx|packets"
    sleep 30
done