#!/bin/bash

# Source IP Preservation Processor Configuration 
# Maintains original source IPs from AWS Traffic Mirroring through to GKE

# Get configuration from environment
SRC_NET=${SRC_NET:-"10.11.0.0/24"}
DST_NET=${DST_NET:-"10.12.0.0/24"}
GKE_SERVICE_IP=${GKE_SERVICE_IP:-"10.13.0.100"}
GKE_SERVICE_PORT=${GKE_SERVICE_PORT:-"2055"}

HOST_ETH0_MAC=$(cat /sys/class/net/eth0/address)
HOST_ETH1_MAC=$(cat /sys/class/net/eth1/address)

cat > /tmp/vpp-source-ip-processor.conf << EOF
# Source IP Preservation Processor Configuration

# Enable required plugins
plugins {
    plugin af_packet_plugin.so { enable }
    plugin nat_plugin.so { enable } 
    plugin ipsec_plugin.so { enable }
    plugin dpdk_plugin.so { disable }
}

# Create host interfaces
create host-interface name eth0 hw-addr $HOST_ETH0_MAC
create host-interface name eth1 hw-addr $HOST_ETH1_MAC

# Set interfaces up
set interface state host-eth0 up
set interface state host-eth1 up

# Configure IP addresses
set interface ip address host-eth0 10.11.0.20/24
set interface ip address host-eth1 10.12.0.10/24

# Configure MTU to handle DF bit packets from AWS VXLAN decapsulation
set interface mtu packet 1400 host-eth0
set interface mtu packet 1400 host-eth1

# Configure routing for source IP preservation
ip route add 0.0.0.0/0 via 10.12.0.1 host-eth1
ip route add 10.11.0.0/24 via 10.11.0.1 host-eth0

# Configure NAT44 for source IP passthrough mode
# Key: We bypass NAT for flows that need source IP preserved
nat44 plugin enable sessions 50000

# Set NAT44 interfaces
set interface nat44 in host-eth0
set interface nat44 out host-eth1

# Create ACL to identify traffic that should preserve source IP
create acl-plugin acl 1 
  rule 1 action permit src 0.0.0.0/0 dst $GKE_SERVICE_IP/32 proto 17 sport 0-65535 dport $GKE_SERVICE_PORT

# Apply ACL to bypass NAT for netflow/sflow/ipfix traffic
set acl-plugin interface host-eth0 input acl 1

# Configure source IP preservation using policy routing
create classifier table mask l3 src,dst,sport,dport next-node ip4-classify
create classifier session table-index 0 \\
  match l3 dst $GKE_SERVICE_IP proto 17 dport $GKE_SERVICE_PORT \\
  action set-ip4-fib-id 1

# Create dedicated FIB for preserved source IP traffic
ip table add 1
ip route add table 1 0.0.0.0/0 via 10.12.0.1 host-eth1

# Configure IPFIX/NetFlow/sFlow preservation
# Create special handling for flow monitoring protocols
create sub-interface host-eth1 100
set interface state host-eth1.100 up
set interface ip address host-eth1.100 10.12.0.11/24

# Set up load balancing for multiple GKE endpoints
ip route add table 1 $GKE_SERVICE_IP/32 \\
  via 10.13.0.100 host-eth1 weight 1 \\
  via 10.13.0.101 host-eth1 weight 1 \\
  via 10.13.0.102 host-eth1 weight 1

# Configure packet replication for high availability
create packet-replicator src host-eth0 dst host-eth1 ratio 1:1

# Configure DF bit handling for source IP preservation
# Enable IP reassembly for fragmented packets  
ip reassembly enable-disable ipv4 on
ip reassembly max-reassemblies 2048
ip reassembly max-reassembly-length 65535
ip reassembly expire-walk-interval 10000

# Handle DF bit for UDP packets (NetFlow/sFlow/IPFIX)
# UDP packets with DF=1 that exceed MTU need special handling
create classify table mask l3 proto next-node ip4-fragmentation-midchain
create classify session table-index 0 \\
  match l3 proto 17 \\
  action set-ip4-fib-id 0

# Configure UDP fragmentation bypass for DF=1 packets
# Clear DF bit for UDP packets that need fragmentation
ip fragmentation df-bit clear

# Enable features for source IP handling and UDP DF bit processing  
set interface feature host-eth0 ip4-classify arc ip4-unicast
set interface feature host-eth0 ip4-reassembly arc ip4-unicast
set interface feature host-eth1 nat44-out arc ip4-output
set interface feature host-eth1 ip4-fragmentation-midchain arc ip4-output

# Configure ARP for next-hop resolution
set ip arp static host-eth0 10.11.0.1 auto
set ip arp static host-eth1 10.12.0.1 auto

# Set up monitoring for source IP preservation
create tap id 1 host-if-name source-ip-monitor
set interface state tap1 up
set interface ip address tap1 10.200.2.1/24

# Configure packet mirroring for debugging
set interface span host-eth0 destination tap1 both

# Performance optimizations
set interface rx-mode host-eth0 polling worker 0
set interface rx-mode host-eth1 polling worker 1

# Enable detailed tracing for source IP flows
trace add af-packet-input 100
trace add ip4-input 100
trace add nat44-in2out 50
trace add nat44-out2in 50

EOF

echo "Starting VPP with source IP preservation configuration..."
vpp -c /vpp-common/startup.conf &
sleep 5

echo "Applying source IP preservation configuration..."
vppctl exec /tmp/vpp-source-ip-processor.conf

# Configure Linux networking for source IP passthrough
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter
echo 2 > /proc/sys/net/ipv4/conf/all/arp_announce
echo 1 > /proc/sys/net/ipv4/conf/all/arp_ignore

# Set up iptables rules for source IP preservation
iptables -t mangle -F
iptables -t mangle -A PREROUTING -p udp --dport $GKE_SERVICE_PORT -j MARK --set-mark 100
iptables -t nat -A POSTROUTING -m mark --mark 100 -j ACCEPT

# Configure policy routing for marked packets
ip rule add fwmark 100 table 100 pref 100
ip route add table 100 default via 10.12.0.1 dev eth1

# Monitor source IP preservation
echo "Source IP preservation configured. Monitoring..."
while true; do
    echo "$(date): NAT44 sessions with source IP preservation:"
    vppctl show nat44 sessions | grep -v "total sessions"
    echo "$(date): Classifier table stats:"
    vppctl show classify tables verbose
    echo "$(date): Interface counters:"
    vppctl show interface | grep -E "(host-eth[01]|packets)"
    sleep 30
done