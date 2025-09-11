#!/bin/bash

# AWS Mirror Target EC2 Configuration - Based on Architecture Diagrams
# Handles VXLAN decapsulation, MAC rewriting, DNAT, and br0 bridge setup

# Configuration from environment and diagrams
PRIMARY_ENI_MAC="aa:bb:cc:00:00:02"    # Primary ENI MAC from diagram
SECONDARY_ENI_MAC="de:ad:be:ef:56:78"  # Secondary ENI MAC from diagram
PRIMARY_ENI_IP="10.0.0.10"             # Primary ENI IP
SECONDARY_ENI_IP="10.0.0.20"           # Secondary ENI IP (moved to br0)
BR0_IP="10.0.0.20"                     # br0 bridge IP from diagram
VXLAN_PORT=4789                        # VXLAN port from AWS Traffic Mirror
ORIGINAL_DST_PORT=31756                # Original destination port
TARGET_DST_PORT=8081                   # Target destination port (FDI)

cat > /tmp/vpp-aws-target-ec2.conf << EOF
# AWS Mirror Target EC2 Configuration - Exact match to diagrams

# Enable plugins for AWS Traffic Mirror processing
plugins {
    plugin af_packet_plugin.so { enable }
    plugin vxlan_plugin.so { enable }
    plugin nat_plugin.so { enable }
    plugin l2_plugin.so { enable }
    plugin classify_plugin.so { enable }
}

# Create host interfaces with exact MAC addresses from diagram
create host-interface name eth0 hw-addr $PRIMARY_ENI_MAC
create host-interface name eth1 hw-addr $SECONDARY_ENI_MAC

# Set interfaces to up state
set interface state host-eth0 up
set interface state host-eth1 up

# Configure interface IP addresses matching diagram
set interface ip address host-eth0 $PRIMARY_ENI_IP/24
# Note: eth1 IP will be moved to br0 bridge as shown in diagram

# Create VXLAN tunnel for AWS Traffic Mirror (port 4789)
create vxlan tunnel src $PRIMARY_ENI_IP dst auto port $VXLAN_PORT vni auto decap-next l2

# Set VXLAN tunnel interface up
set interface state vxlan_tunnel0 up

# Configure MTU for VXLAN tunnel to handle DF bit packets
set interface mtu packet 1450 vxlan_tunnel0

# Create bridge domain br0 (matching diagram)
create bridge-domain 1 learn 1 forward 1 uu-flood 1 flood 1 arp-term 1

# Add VXLAN tunnel to bridge domain
set interface l2 bridge vxlan_tunnel0 1

# Create loopback interface for br0 functionality
create loopback interface instance 0
set interface state loop0 up
set interface ip address loop0 $BR0_IP/24

# Add loopback to bridge domain as BVI (Bridge Virtual Interface)
set interface l2 bridge loop0 1 bvi

# Configure DNAT for port translation (31756 → 8081)
nat44 plugin enable sessions 10000 endpoint-dependent

# Set NAT44 interfaces  
set interface nat44 in loop0
set interface nat44 out host-eth1

# Add DNAT static mapping (port 31756 → 8081)
nat44 add static mapping local $SECONDARY_ENI_IP $ORIGINAL_DST_PORT external $SECONDARY_ENI_IP $TARGET_DST_PORT

# Configure MAC address handling for AWS ENI compliance
# Handle destination MAC changes as shown in diagram
create classify table mask l2.dst next-node l2-input-classify
create classify session table-index 0 \\
  match l2.dst $SECONDARY_ENI_MAC \\
  action set-ip4-fib-id 0

# Configure Layer 3 routing after MAC processing
ip route add 0.0.0.0/0 via 10.0.0.1 host-eth1

# Handle DF bit packets for UDP traffic (NetFlow/sFlow/IPFIX)
ip reassembly enable-disable ipv4 on
ip reassembly max-reassemblies 1024
ip reassembly max-reassembly-length 30000

# Clear DF bit for UDP packets that need fragmentation  
ip fragmentation df-bit clear

# Configure packet classification for flow monitoring protocols
create classify table mask l3 proto,dst_port next-node nat44-in2out
create classify session table-index 1 \\
  match l3 proto 17 dst_port $ORIGINAL_DST_PORT \\
  action set-ip4-fib-id 0

# Set interface features for AWS processing pipeline
set interface feature vxlan_tunnel0 l2-input arc l2-input
set interface feature loop0 nat44-in2out arc ip4-unicast  
set interface feature host-eth1 nat44-out2in arc ip4-output

# Configure ARP for proper forwarding
set ip arp static loop0 10.0.0.1 auto
set ip arp static host-eth1 10.0.0.1 auto

# Enable packet tracing for debugging AWS traffic flow
trace add af-packet-input 50
trace add vxlan4-input 50
trace add l2-input 50
trace add nat44-in2out 50
trace add nat44-out2in 50

# Performance optimizations for AWS workloads
set interface rx-mode host-eth0 polling worker 0
set interface rx-mode host-eth1 polling worker 1

EOF

echo "Starting VPP with AWS Target EC2 configuration..."
vpp -c /vpp-common/startup.conf &
sleep 5

echo "Applying AWS Target EC2 configuration..."
vppctl exec /tmp/vpp-aws-target-ec2.conf

# Create Linux br0 bridge to match diagram exactly
echo "Setting up Linux br0 bridge (matching diagram)..."
brctl addbr br0 2>/dev/null || true
brctl setfd br0 0 2>/dev/null || true  
brctl stp br0 off 2>/dev/null || true
ip link set br0 up
ip addr add $BR0_IP/24 dev br0

# Move secondary ENI IP to br0 bridge as shown in diagram  
ip addr del $SECONDARY_ENI_IP/24 dev eth1 2>/dev/null || true
ip addr add $SECONDARY_ENI_IP/24 dev br0

# Configure iptables for DNAT (matching diagram logic)
echo "Configuring iptables for DNAT processing..."
iptables -t nat -F
iptables -t nat -A PREROUTING -p udp --dport $ORIGINAL_DST_PORT -j DNAT --to-destination :$TARGET_DST_PORT
iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE

# Enable forwarding and disable reverse path filtering
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter
echo 0 > /proc/sys/net/ipv4/conf/eth0/rp_filter
echo 0 > /proc/sys/net/ipv4/conf/eth1/rp_filter
echo 0 > /proc/sys/net/ipv4/conf/br0/rp_filter

# Configure routing to match diagram flow
echo "Setting up routing for AWS → GCP flow..."
# Route for traffic going to FDI (GCP)
ip route add 100.76.10.11/32 via 10.0.0.1 dev eth1

# Monitor AWS Target EC2 processing
echo "AWS Target EC2 configured. Monitoring traffic processing..."
while true; do
    echo "$(date): AWS Target EC2 Stats:"
    echo "=========================="
    
    echo "VXLAN Tunnel (AWS Traffic Mirror input):"
    vppctl show vxlan tunnel | grep -E "(rx|tx) packets"
    
    echo "Bridge Domain br0:"
    vppctl show bridge-domain 1 detail | grep -E "rx|tx|packets"
    
    echo "NAT44 Sessions (DNAT 31756→8081):"
    vppctl show nat44 sessions | grep -E "$ORIGINAL_DST_PORT|$TARGET_DST_PORT"
    
    echo "Interface Statistics:"
    vppctl show interface | grep -E "(host-eth|vxlan|loop)" -A 2
    
    echo "Linux Bridge br0 Status:"
    brctl show br0
    ip addr show br0 | grep inet
    
    sleep 30
done