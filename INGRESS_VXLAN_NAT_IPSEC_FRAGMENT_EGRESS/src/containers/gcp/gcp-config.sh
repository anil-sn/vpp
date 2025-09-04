#!/bin/bash
set -e

echo "--- Configuring GCP Container (Simplified) ---
"

# Create interface on underlay network
vppctl create host-interface name eth0
vppctl set interface ip address host-eth0 172.20.5.20/24
vppctl set interface state host-eth0 up

# Create TAP interface for Linux integration and packet capture
vppctl create tap id 0 host-if-name vpp-tap0
vppctl set interface ip address tap0 10.0.3.1/24
vppctl set interface state tap0 up



# Set up routing
# Default route to underlay gateway
vppctl ip route add 0.0.0.0/0 via 172.20.5.1

# Route local subnet to TAP for Linux processing
vppctl ip route add 10.0.3.0/24 via tap0

# Configure Linux side of TAP interface
ip addr add 10.0.3.2/24 dev vpp-tap0 || echo "TAP already configured"
ip link set vpp-tap0 up || echo "TAP already up"

# Start packet capture service on TAP interface
tcpdump -i vpp-tap0 -w /tmp/gcp-received.pcap &
TCPDUMP_PID=$!

echo "--- GCP Interfaces (Simplified) ---
"
vppctl show interface addr

echo "--- GCP Routes (Simplified) ---
"
vppctl show ip fib

echo "--- Linux TAP Interface (Simplified) ---
"
ip addr show vpp-tap0

echo "--- Packet capture started on TAP interface (PID: $TCPDUMP_PID) ---
"
echo "--- GCP Simplified configuration completed ---
"