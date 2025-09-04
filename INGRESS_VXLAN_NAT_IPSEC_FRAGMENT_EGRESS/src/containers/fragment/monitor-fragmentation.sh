#!/bin/bash
# Fragment monitoring script for VPP fragmentation container

echo "=== VPP Fragment Container Monitoring ==="
echo "Timestamp: $(date)"
echo

# Interface statistics
echo "--- Interface Statistics ---"
docker exec chain-fragment vppctl show interface

# Fragment statistics
echo -e "\n--- Fragment Statistics ---" 
docker exec chain-fragment vppctl show ip frag

# MTU information
echo -e "\n--- Interface MTU ---"
docker exec chain-fragment vppctl show interface mtu

# Memory usage
echo -e "\n--- Memory Usage ---"
docker exec chain-fragment vppctl show memory

# Trace if available
echo -e "\n--- Recent Traces (last 10) ---"
docker exec chain-fragment vppctl show trace | head -20

echo -e "\n=== End Fragment Monitor ==="