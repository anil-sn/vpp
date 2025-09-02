#!/bin/bash
# setup.sh
#
# This script builds the complete test environment from a clean slate.
# It must be run with sudo because it creates and modifies host network interfaces.

# Exit immediately if any command fails.
set -e

# --- 1. Host Network Setup ---
# This section creates the "physical" underlay network on the host machine.
echo "--- Preparing host environment... ---"
sudo ip link add name br0 type bridge || true
sudo ip link set br0 up

# --- 2. Docker Container Setup ---
# Launch the two containers that will act as our separate network nodes.
echo "--- Creating Docker containers (aws_vpp & gcp_vpp)... ---"
docker run -d --name aws_vpp --privileged -v "$(pwd)/aws-startup.conf:/etc/vpp/startup.conf" -it vpp-forwarder:latest
docker run -d --name gcp_vpp --privileged -v "$(pwd)/gcp-startup.conf:/etc/vpp/startup.conf" -it vpp-forwarder:latest

# --- 3. Network Plumbing for AWS ---
echo "--- Waiting for aws_vpp network namespace... ---"
AWS_PID=$(docker inspect -f '{{.State.Pid}}' aws_vpp)
while [ ! -f /proc/$AWS_PID/ns/net ]; do
  sleep 0.1
done
echo "aws_vpp network namespace is ready."

sudo ip link delete aws-phy 2>/dev/null || true
sudo ip link delete aws-br 2>/dev/null || true

echo "Creating veth pair for aws_vpp..."
sudo ip link add aws-phy type veth peer name aws-br
sudo ip link set aws-phy netns $AWS_PID
sudo ip link set aws-br master br0
sudo ip link set aws-br up

# --- 4. Network Plumbing for GCP ---
echo "--- Waiting for gcp_vpp network namespace... ---"
GCP_PID=$(docker inspect -f '{{.State.Pid}}' gcp_vpp)
while [ ! -f /proc/$GCP_PID/ns/net ]; do
  sleep 0.1
done
echo "gcp_vpp network namespace is ready."

sudo ip link delete gcp-phy 2>/dev/null || true
sudo ip link delete gcp-br 2>/dev/null || true

echo "Creating veth pair for gcp_vpp..."
sudo ip link add gcp-phy type veth peer name gcp-br
sudo ip link set gcp-phy netns $GCP_PID
sudo ip link set gcp-br master br0
sudo ip link set gcp-br up

# --- 5. VPP Initialization ---
echo "--- Waiting for VPP to initialize... ---"
for C in aws_vpp gcp_vpp; do
    echo "Waiting for VPP in ${C}..."
    until docker exec ${C} test -S /run/vpp/cli.sock; do sleep 1; done
    echo "VPP in ${C} is ready."
done

# --- 6. Apply VPP Configurations ---
echo "--- Copying and applying VPP configurations... ---"
docker cp aws-config.sh aws_vpp:/root/aws-config.sh
docker cp gcp-config.sh gcp_vpp:/root/gcp-config.sh
docker exec aws_vpp bash /root/aws-config.sh
docker exec gcp_vpp bash /root/gcp-config.sh

echo "--- Setup complete! ---"