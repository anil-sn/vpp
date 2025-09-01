#!/bin/bash

# A simple script to set up HugePages for DPDK

# Allocate 1024 hugepages on NUMA node 0.
# Check your memory requirements and adjust as needed.
echo 1024 | sudo tee /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages

# Mount the HugePages filesystem.
sudo mkdir -p /mnt/huge
sudo mount -t hugetlbfs nodev /mnt/huge

echo "HugePages setup complete for NUMA node 0."
