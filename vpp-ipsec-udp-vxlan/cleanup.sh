#!/bin/bash
#
# cleanup.sh
#
# This script is responsible for tearing down all components of the test environment.
# It is designed to be idempotent, meaning it can be run multiple times without
# causing errors if the resources it tries to delete are already gone.
# It must be run with sudo because it modifies host network interfaces.

# Exit immediately if any command fails.
set -e

echo "Cleaning up setup..."

# --- Step 1: Stop and Remove Docker Containers ---
# Use the new container names 'aws_vpp' and 'gcp_vpp'.
echo "Stopping and removing Docker containers..."
docker stop aws_vpp gcp_vpp || true
docker rm aws_vpp gcp_vpp || true

# --- Step 2: Remove Host-Side Network Interfaces (veth pairs) ---
# This deletes the host-side ends of the veth pairs ('aws-br' and 'gcp-br').
# '2>/dev/null || true' suppresses the "Cannot find device" error if the
# interface doesn't exist.
echo "Removing veth pairs..."
sudo ip link delete aws-br 2>/dev/null || true
sudo ip link delete gcp-br 2>/dev/null || true

# --- Step 3: Remove Host Bridge ---
# Deletes the Linux bridge that connected the two containers.
echo "Removing bridge br0..."
sudo ip link delete br0 2>/dev/null || true

echo "Cleanup complete!"