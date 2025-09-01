#!/bin/bash
# setup.sh
#
# This script builds the complete test environment from a clean slate.
# It must be run with sudo because it creates and modifies host network interfaces.

# Exit immediately if any command fails.
set -e

# --- 1. Host Network Setup ---
# This section creates the "physical" underlay network on the host machine.
# In a real-world scenario, this would be a physical switch connecting two servers.
# Here, we simulate it with a Linux bridge.
echo "--- Preparing host environment... ---"
# '|| true' ensures that if the bridge already exists, the command doesn't fail.
sudo ip link add name br0 type bridge || true
# Set the MTU to 9000. This is the crucial step that enables jumbo frames on the
# underlay network. Every interface connected to this bridge must also have this MTU.
sudo ip link set br0 mtu 9000
sudo ip link set br0 up

# --- 2. Docker Container Setup ---
# Launch the two containers that will act as our separate network nodes (AWS & GCP).
# The containers are run in privileged mode to allow them to manipulate their
# own network stacks and interact with VPP.
# We mount the respective startup.conf file into each container.
echo "--- Creating Docker containers (AWS & GCP)... ---"
docker run -d --name AWS --privileged -v "$(pwd)/aws-startup.conf:/etc/vpp/startup.conf" -it vpp-iperf:latest
docker run -d --name GCP --privileged -v "$(pwd)/gcp-startup.conf:/etc/vpp/startup.conf" -it vpp-iperf:latest

# --- 3. Network Plumbing for AWS ---
echo "--- Waiting for AWS network namespace... ---"
# Get the Process ID (PID) of the running container.
AWS_PID=$(docker inspect -f '{{.State.Pid}}' AWS)
# The container's network namespace is a file in the /proc filesystem. We must wait
# for this file to exist before we can move an interface into it. This loop
# prevents a race condition where the 'ip link set netns' command could fail.
while [ ! -f /proc/$AWS_PID/ns/net ]; do
  sleep 0.1
done
echo "AWS network namespace is ready."

# Ensure a clean slate by explicitly deleting any interfaces left over from
# a previously failed run. This makes the script robust and idempotent.
# Redirecting stderr to /dev/null to suppress "Cannot find device" if it's already clean.
sudo ip link delete aws-phy 2>/dev/null || true
sudo ip link delete aws-br 2>/dev/null || true

echo "Creating veth pair for AWS..."
# Create a virtual Ethernet (veth) pair. It's like a virtual patch cable.
# 'aws-phy' is the end that will go inside the container (the "physical" NIC).
# 'aws-br' is the end that will connect to our host bridge.
sudo ip link add aws-phy type veth peer name aws-br
# An interface MUST be in the DOWN state before it can be moved into a different
# network namespace.
sudo ip link set aws-phy down
sudo ip link set aws-phy netns $AWS_PID
# Connect the host-side end of the cable to the bridge.
sudo ip link set aws-br master br0
# Set the MTU of the host-side end to 9000 to match the bridge.
sudo ip link set aws-br mtu 9000
sudo ip link set aws-br up

# --- 4. Network Plumbing for GCP ---
# This section repeats the exact same logic as above for the GCP container.
echo "--- Waiting for GCP network namespace... ---"
GCP_PID=$(docker inspect -f '{{.State.Pid}}' GCP)
while [ ! -f /proc/$GCP_PID/ns/net ]; do
  sleep 0.1
done
echo "GCP network namespace is ready."

sudo ip link delete gcp-phy 2>/dev/null || true
sudo ip link delete gcp-br 2>/dev/null || true

echo "Creating veth pair for GCP..."
sudo ip link add gcp-phy type veth peer name gcp-br
sudo ip link set gcp-phy down
sudo ip link set gcp-phy netns $GCP_PID
sudo ip link set gcp-br master br0
sudo ip link set gcp-br mtu 9000
sudo ip link set gcp-br up

# --- 5. VPP Initialization ---
echo "--- Waiting for VPP to initialize... ---"
# Even after the container is running, the VPP process inside takes a few
# seconds to initialize. We wait until its command-line interface socket
# '/run/vpp/cli.sock' is created before trying to send it commands.
for C in AWS GCP; do
    echo "Waiting for VPP in ${C}..."
    until docker exec ${C} test -S /run/vpp/cli.sock; do sleep 1; done
    echo "VPP in ${C} is ready."
done

# --- 6. Apply VPP Configurations ---
# With the environment fully plumbed, we now copy and execute the specific
# configuration scripts inside each container.
echo "--- Copying and applying VPP configurations... ---"
docker cp aws-config.sh AWS:/root/aws-config.sh
docker cp gcp-config.sh GCP:/root/gcp-config.sh
docker exec AWS bash /root/aws-config.sh
docker exec GCP bash /root/gcp-config.sh

echo "--- Setup complete! ---"