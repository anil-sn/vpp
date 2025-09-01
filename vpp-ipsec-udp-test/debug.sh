#!/bin/bash
#
# debug.sh
#
# This script is a standalone debugging tool to collect detailed state
# information from all components of the test environment. It can be run after
# a test to inspect the final state of the system.

echo "================================================================"
echo " HOST NETWORK STATE"
echo "================================================================"
echo "--- Host Interfaces ---"
# 'ip a' shows all host interfaces, their IP addresses, and state.
ip a
echo
echo "--- Host Bridge Details ---"
# 'brctl show' displays the Linux bridge and which interfaces are connected to it.
sudo brctl show br0
echo

echo "================================================================"
echo " AWS CONTAINER & VPP STATE"
echo "================================================================"
echo "--- AWS: Linux Interfaces (ip a) ---"
# Shows interfaces from the perspective of the container's Linux kernel.
docker exec AWS ip a
echo
echo "--- AWS: Linux Routes (ip route) ---"
# Shows the routing table of the container's Linux kernel.
docker exec AWS ip route
echo
echo "--- AWS: VPP Interfaces (vppctl show int) ---"
# Shows all VPP interfaces, their state, and packet counters.
docker exec AWS vppctl show int
echo
echo "--- AWS: VPP Interface Addresses (vppctl show int addr) ---"
# Shows only the IP addresses assigned to VPP interfaces.
docker exec AWS vppctl show int addr
echo
echo "--- AWS: VPP Forwarding Table (vppctl show ip fib) ---"
# Dumps VPP's Forwarding Information Base (routing table).
docker exec AWS vppctl show ip fib
echo
echo "--- AWS: VPP IPsec SAs (vppctl show ipsec sa) ---"
# Shows the configured IPsec Security Associations.
docker exec AWS vppctl show ipsec sa
echo
echo "--- AWS: VPP Tunnels (vppctl show tunnel) ---"
# Shows the configured tunnel interfaces.
docker exec AWS vppctl show tunnel
echo

echo "================================================================"
echo " GCP CONTAINER & VPP STATE"
echo "================================================================"
echo "--- GCP: Linux Interfaces (ip a) ---"
docker exec GCP ip a
echo
echo "--- GCP: Linux Routes (ip route) ---"
docker exec GCP ip route
echo
echo "--- GCP: VPP Interfaces (vppctl show int) ---"
docker exec GCP vppctl show int
echo
echo "--- GCP: VPP Interface Addresses (vppctl show int addr) ---"
docker exec GCP vppctl show int addr
echo
echo "--- GCP: VPP Forwarding Table (vppctl show ip fib) ---"
docker exec GCP vppctl show ip fib
echo

echo "================================================================"
echo " LIVE PING & TRACE (EXAMPLE)"
echo "================================================================"
echo "--- Clearing old traces and enabling new packet traces on AWS ---"
# Note: VPP trace commands can be version-specific. This is an example.
docker exec AWS vppctl clear trace
# Trace packets coming from Linux into VPP (tap0).
docker exec AWS vppctl trace add tap-input 50 || true
# Trace packets coming from the underlay into VPP (host-aws-phy).
docker exec AWS vppctl trace add af-packet-input 50 || true
echo
echo "--- Attempting Ping from AWS to GCP ---"
docker exec AWS ping -c 3 10.0.2.1 || true
echo
echo "--- AWS Packet Trace Results ---"
docker exec AWS vppctl show trace
echo

echo "================================================================"
echo " DEBUGGING COMPLETE"
echo "================================================================"