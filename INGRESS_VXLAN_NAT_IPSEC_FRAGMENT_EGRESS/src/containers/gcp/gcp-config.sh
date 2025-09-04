#!/bin/bash
set -e

echo "--- Configuring GCP Container (Destination Endpoint) ---"

# Wait for interfaces to be available
sleep 5

# Create interface on underlay network
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 192.168.10.3/24
vppctl set interface state host-eth0 up

# Create TAP interface for Linux integration and packet capture
vppctl create tap id 0 host-if-name vpp-tap0
vppctl set interface ip address tap0 10.0.3.1/24
vppctl set interface state tap0 up

# Set up routing
# Default route to underlay gateway
vppctl ip route add 0.0.0.0/0 via 192.168.10.1

# Route local subnet to TAP for Linux processing
vppctl ip route add 10.0.3.0/24 via tap0

# Enable IP forwarding
vppctl set interface feature host-eth0 ip4-unicast-rx on
vppctl set interface feature tap0 ip4-unicast-tx on

# Enable IP reassembly for fragmented packets
vppctl set interface feature host-eth0 ip4-full-reassembly-feature on

# Enable packet tracing
vppctl clear trace
vppctl trace add af-packet-input 50
vppctl trace add ip4-full-reassembly-feature 50

# Configure Linux side of TAP interface
ip addr add 10.0.3.2/24 dev vpp-tap0 || echo "TAP already configured"
ip link set vpp-tap0 up || echo "TAP already up"

# Start packet capture service on TAP interface
tcpdump -i vpp-tap0 -w /tmp/gcp-received.pcap &
TCPDUMP_PID=$!

echo "--- GCP Interfaces ---"
vppctl show interface addr

echo "--- GCP Routes ---"
vppctl show ip fib

echo "--- Linux TAP Interface ---"
ip addr show vpp-tap0

echo "--- Packet capture started on TAP interface (PID: $TCPDUMP_PID) ---"
echo "--- GCP configuration completed ---"