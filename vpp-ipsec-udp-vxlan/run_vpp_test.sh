#!/bin/bash
#
# run_vpp_test.sh
#
# This is the master script to execute the VXLAN -> NAT -> IPsec simulation.
# It ensures a consistent and clean environment for every run by following a strict
# build -> cleanup -> setup sequence, and then provides instructions for testing.
# It must be run with sudo because it modifies host network interfaces.

# Exit immediately if any command fails.
set -e

# --- Step 1: Build the Docker Image ---
# This command builds the Docker image defined in 'Dockerfile'.
# We tag it as 'vpp-forwarder:latest' for easy reference in the setup script.
echo "--- Step 1: Building Docker image... ---"
docker build -t vpp-forwarder:latest .

# --- Step 2: Run the Cleanup Script ---
# This ensures that any resources from a previous run are completely removed.
echo "--- Step 2: Cleaning up previous environment... ---"
sudo bash ./cleanup.sh

# --- Step 3: Run the Setup Script ---
# This script builds the test environment from scratch.
echo "--- Step 3: Setting up new test environment... ---"
sudo bash ./setup.sh

# --- Step 4: Display Status and Instructions ---
echo
echo "--- Waiting a few seconds for IPsec tunnel to establish... ---"
sleep 5

echo
echo "==================== IPsec SA Status ===================="
echo "--- AWS VPP SAs: ---"
docker exec aws_vpp vppctl show ipsec sa
echo
echo "--- GCP VPP SAs: ---"
docker exec gcp_vpp vppctl show ipsec sa
echo "========================================================="
echo

echo "********** ENVIRONMENT IS READY **********"
echo
echo "In a new terminal, run the following command to send traffic:"
echo "  python3 send_flows.py"
echo
echo "Use the debug script to verify the results:"
echo "  sudo bash ./debug.sh aws_vpp show nat44 sessions"
echo "  sudo bash ./debug.sh gcp_vpp show trace"
echo