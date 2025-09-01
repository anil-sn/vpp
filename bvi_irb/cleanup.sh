#!/bin/bash
#
# Cleans up the VPP IRB lab environment.
#

set +e # Continue even if some commands fail

CONTAINER_NAME="vpp-irb-lab"

echo "Stopping and removing Docker container: ${CONTAINER_NAME}..."
sudo docker stop ${CONTAINER_NAME} >/dev/null 2>&1
sudo docker rm ${CONTAINER_NAME} >/dev/null 2>&1

echo "Deleting network namespaces..."
sudo ip netns del ns1 >/dev/null 2>&1
sudo ip netns del ns2 >/dev/null 2>&1
sudo ip netns del ns3 >/dev/null 2>&1

# The veth pairs are automatically deleted when the netns are deleted,
# but we run this just in case they were left orphaned.
echo "Deleting leftover tap interfaces on host..."
sudo ip link del tap0 >/dev/null 2>&1
sudo ip link del tap1 >/dev/null 2>&1
sudo ip link del tap2 >/dev/null 2>&1

echo "Cleanup complete."
