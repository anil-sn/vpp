#!/bin/bash

# GKE Forwarder Configuration
# Forwards preserved source IP traffic to GKE services

# Get configuration from environment  
GKE_SERVICE_NAME=${GKE_SERVICE_NAME:-"netflow-processor"}
GKE_NAMESPACE=${GKE_NAMESPACE:-"default"}
GKE_SERVICE_PORT=${GKE_SERVICE_PORT:-"2055"}
GKE_CLUSTER_IP=${GKE_CLUSTER_IP:-"10.13.0.100"}

HOST_ETH0_MAC=$(cat /sys/class/net/eth0/address)
HOST_ETH1_MAC=$(cat /sys/class/net/eth1/address)

cat > /tmp/vpp-gke-forwarder.conf << EOF
# GKE Service Forwarder Configuration with Source IP Preservation

# Enable plugins for GKE integration
plugins {
    plugin af_packet_plugin.so { enable }
    plugin lb_plugin.so { enable }
    plugin nat_plugin.so { enable }
    plugin http_static_plugin.so { enable }
}

# Create host interfaces
create host-interface name eth0 hw-addr $HOST_ETH0_MAC  
create host-interface name eth1 hw-addr $HOST_ETH1_MAC

# Set interfaces up
set interface state host-eth0 up
set interface state host-eth1 up

# Configure IP addresses
set interface ip address host-eth0 10.12.0.20/24
set interface ip address host-eth1 10.13.0.10/24

# Configure default routing to GKE cluster
ip route add 0.0.0.0/0 via 10.13.0.1 host-eth1
ip route add 10.12.0.0/24 via 10.12.0.1 host-eth0

# Create load balancer VIP for GKE service
lb conf ip4-src-address 10.13.0.10 buckets 1024 timeout 300

# Add GKE service endpoints to load balancer
lb vip 10.13.0.100 port $GKE_SERVICE_PORT protocol udp
lb as 10.13.0.100 port $GKE_SERVICE_PORT protocol udp \\
  10.13.0.101:$GKE_SERVICE_PORT 10.13.0.102:$GKE_SERVICE_PORT 10.13.0.103:$GKE_SERVICE_PORT

# Configure source IP preservation for load balanced traffic  
create classifier table mask l3 src next-node lb4-nodeport
create classifier session table-index 0 \\
  match l3 src 0.0.0.0 mask 255.255.255.255 \\
  action set-ip4-fib-id 0

# Create TAP interface for GKE integration monitoring
create tap id 0 host-if-name gke-tap0 host-bridge gke-br0
set interface state tap0 up
set interface ip address tap0 10.200.0.1/24

# Configure packet capture for debugging
set interface span host-eth0 destination tap0 both
set pcap trace on max 1000 file /var/log/vpp/gke-traffic.pcap

# Enable health checking for GKE endpoints
create health-check test-name gke-health \\
  type http \\
  interval 10 \\
  timeout 5 \\
  failure-count 3 \\
  success-count 2

# Configure NAT44 for return traffic (preserve client source)
nat44 plugin enable sessions 10000 endpoint-dependent
set interface nat44 out host-eth1

# Create policy for GKE service traffic identification
create acl-plugin acl 2
  rule 1 action permit src 0.0.0.0/0 dst $GKE_CLUSTER_IP/32 proto 17 dport $GKE_SERVICE_PORT

set acl-plugin interface host-eth0 input acl 2

# Configure ECMP for GKE pod distribution
ip route add $GKE_CLUSTER_IP/32 \\
  via 10.13.0.101 host-eth1 weight 1 \\
  via 10.13.0.102 host-eth1 weight 1 \\
  via 10.13.0.103 host-eth1 weight 1

# Set up service mesh integration (if applicable)
create service-mesh endpoint gke-netflow \\
  ip $GKE_CLUSTER_IP \\
  port $GKE_SERVICE_PORT \\
  protocol udp \\
  health-check gke-health

# Configure ARP for GKE cluster communication
set ip arp static host-eth1 10.13.0.1 auto
set ip arp static host-eth1 10.13.0.101 auto 
set ip arp static host-eth1 10.13.0.102 auto
set ip arp static host-eth1 10.13.0.103 auto

# Enable features for GKE traffic processing
set interface feature host-eth0 acl-plugin-in-ip4-fa arc ip4-unicast
set interface feature host-eth1 lb-nat4 arc ip4-output

# Performance optimizations for GKE forwarding
set interface rx-mode host-eth0 polling worker 0
set interface rx-mode host-eth1 polling worker 1

# Configure connection tracking for session affinity
nat44 session timeout udp 300 tcp-established 3600 tcp-transitory 60

# Enable monitoring and metrics
create prometheus metrics-server port 9090 
prometheus metric register name vpp_gke_packets_forwarded
prometheus metric register name vpp_gke_sessions_active
prometheus metric register name vpp_gke_health_check_status

# Enable tracing for GKE traffic flow
trace add af-packet-input 50
trace add lb4-nodeport 50  
trace add nat44-out2in 25
trace add ip4-output 25

EOF

echo "Starting VPP with GKE forwarder configuration..."
vpp -c /vpp-common/startup.conf &
sleep 5

echo "Applying GKE forwarder configuration..."
vppctl exec /tmp/vpp-gke-forwarder.conf

# Create Linux bridge for GKE tap interface
brctl addbr gke-br0 2>/dev/null || true
brctl setfd gke-br0 0 2>/dev/null || true
brctl stp gke-br0 off 2>/dev/null || true
ip link set gke-br0 up
ip addr add 10.200.0.2/24 dev gke-br0

# Configure Linux networking for GKE communication
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter

# Set up iptables for GKE service communication
iptables -t nat -F POSTROUTING
iptables -t nat -A POSTROUTING -d $GKE_CLUSTER_IP/32 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE

# Configure policy routing for GKE traffic
ip rule add to $GKE_CLUSTER_IP table 200 pref 200
ip route add table 200 $GKE_CLUSTER_IP via 10.13.0.1 dev eth1

# Set up GKE service discovery via DNS (if applicable)  
echo "nameserver 10.13.0.10" > /etc/resolv.conf
echo "search $GKE_NAMESPACE.svc.cluster.local svc.cluster.local cluster.local" >> /etc/resolv.conf

# Configure health monitoring for GKE endpoints
cat > /tmp/gke-health-check.sh << 'HEALTH_EOF'
#!/bin/bash
while true; do
    for endpoint in 10.13.0.101 10.13.0.102 10.13.0.103; do
        if nc -u -z -w5 $endpoint $GKE_SERVICE_PORT 2>/dev/null; then
            echo "$(date): GKE endpoint $endpoint:$GKE_SERVICE_PORT - HEALTHY"
        else  
            echo "$(date): GKE endpoint $endpoint:$GKE_SERVICE_PORT - UNHEALTHY"
            # Remove from load balancer if unhealthy
            vppctl lb as del 10.13.0.100 port $GKE_SERVICE_PORT protocol udp $endpoint:$GKE_SERVICE_PORT
        fi
    done
    sleep 30
done
HEALTH_EOF

chmod +x /tmp/gke-health-check.sh
/tmp/gke-health-check.sh &

# Monitor GKE forwarding
echo "GKE forwarder configured. Monitoring traffic to GKE services..."
while true; do
    echo "$(date): Load balancer stats:"
    vppctl show lb vips verbose
    echo "$(date): GKE service health:"
    vppctl show health-check
    echo "$(date): NAT44 sessions to GKE:"  
    vppctl show nat44 sessions | grep $GKE_CLUSTER_IP
    sleep 30
done