#!/bin/bash
#
# run_vpp_test.sh
#
# This is the master script to execute the entire VPP IPsec test.
# It ensures a consistent and clean environment for every run by following a strict
# build -> cleanup -> setup -> test sequence.
# It must be run with sudo because it modifies host network interfaces.

# Exit immediately if any command fails, ensuring the script does not proceed
# in an indeterminate state.
set -e

# --- Step 1: Build the Docker Image ---
# This command builds the Docker image defined in 'Dockerfile'.
# We tag it as 'vpp-iperf:latest' for easy reference in the setup script.
# Docker caches layers, so this step is nearly instantaneous on subsequent runs
# unless the Dockerfile is changed.
echo "--- Step 1: Building Docker image... ---"
docker build -t vpp-iperf:latest .

# --- Step 2: Run the Cleanup Script ---
# This is a critical step for idempotency. It ensures that any resources
# (containers, network interfaces) left over from a previous failed run are
# completely removed before starting a new test.
echo "--- Step 2: Cleaning up previous environment... ---"
sudo bash ./cleanup.sh

# --- Step 3: Run the Setup Script ---
# This script builds the test environment from scratch. It creates the host
# bridge, launches the containers, and configures all networking.
echo "--- Step 3: Setting up new test environment... ---"
sudo bash ./setup.sh

# --- Step 4: Run the Test Script ---
# With the environment fully built and configured, this script runs the actual
# verification tests: underlay ping, overlay ping, and the jumbo frame
# fragmentation/reassembly test.
echo "--- Step 4: Executing verification tests... ---"
sudo bash ./test.sh

echo
echo "********** TEST SUITE COMPLETED SUCCESSFULLY **********"