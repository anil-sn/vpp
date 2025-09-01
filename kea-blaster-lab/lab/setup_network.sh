#!/bin/bash
#
# Standalone Network Setup Script for the Kea + BNG Blaster Lab
#
# This script creates the minimal network topology required for the tests.
# It is idempotent, meaning it can be run multiple times to tear down and
# recreate the network, ensuring a clean state.
#
set -e

echo "    - Tearing down and recreating minimal virtual network topology..."

i=1 # Only create the first interface set needed by the tests
srv_if="srv-eth${i}"
cli_if="cli-eth${i}"
vlan_id=$((100 + i))
sub_if="${srv_if}.${vlan_id}"
bridge_if="br${vlan_id}"

# Tear down old interfaces first to ensure a clean slate
ip link del ${bridge_if} 2>/dev/null || true
ip link del ${srv_if} 2>/dev/null || true # This also deletes the veth peer cli-ethX

# Create the new interfaces
ip link add ${srv_if} type veth peer name ${cli_if}
ip link set ${srv_if} up
ip link set ${cli_if} up
ip link add link ${srv_if} name ${sub_if} type vlan id ${vlan_id}
ip link set ${sub_if} up
ip link add name ${bridge_if} type bridge
ip link set ${bridge_if} up
ip link set ${sub_if} master ${bridge_if}
ip addr add 192.10${i}.1.1/16 dev ${bridge_if}
ip -6 addr add 2001:db8:10${i}::1/64 dev ${bridge_if}

echo "    - Waiting for network interfaces to stabilize..."
sleep 2
echo "    - Network is ready."