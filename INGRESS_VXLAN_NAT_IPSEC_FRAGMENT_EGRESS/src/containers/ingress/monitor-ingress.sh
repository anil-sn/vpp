#!/bin/bash
# Ingress monitoring script for VXLAN traffic reception

echo "=== VPP Ingress Container Monitoring ==="
echo "Timestamp: $(date)"
echo

# Interface statistics
echo "--- Interface Statistics ---"
docker exec chain-ingress vppctl show interface

# UDP listener statistics
echo -e "\n--- UDP Statistics ---"  
docker exec chain-ingress vppctl show udp

# VXLAN tunnel status (if configured)
echo -e "\n--- VXLAN Status ---"
docker exec chain-ingress vppctl show vxlan tunnel 2>/dev/null || echo "No VXLAN tunnels configured"

# Packet drops and errors
echo -e "\n--- Error Statistics ---"
docker exec chain-ingress vppctl show errors | head -10

# Runtime information
echo -e "\n--- Runtime Info ---"
docker exec chain-ingress vppctl show runtime | head -10

echo -e "\n=== End Ingress Monitor ==="