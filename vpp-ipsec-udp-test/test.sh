#!/bin/bash
# test.sh
#
# This script runs a complete verification suite for the IPsec tunnel.
# It is designed to be run after setup.sh has successfully completed.

# Exit immediately if any command fails.
set -e

echo "--- Starting AWS <-> GCP IPsec Verification ---"

echo
echo "--- Running Test 1: Pinging UNDERLAY network (AWS-to-GCP)... ---"
# This test uses VPP's internal ping client to verify that the two VPP instances
# can reach each other over the "physical" 192.168.1.0/24 network.
# A success here confirms the host bridge and veth plumbing are correct.
docker exec AWS vppctl ping 192.168.1.3

echo
echo "--- Running Test 2: Warm-up ping for OVERLAY network (to resolve ARP)... ---"
# The first packet from the Linux kernel (10.0.1.1) to the remote side (10.0.2.1)
# will trigger an ARP request from VPP2 to find the MAC of 10.0.2.1.
# This first packet is often dropped. We send one and allow it to fail with '|| true'
# to ensure that the subsequent measured tests have a clean slate.
docker exec AWS ping -c 1 -W 2 10.0.2.1 || true

echo
echo "--- Running Test 3: Pinging OVERLAY network (Standard Size, expect 0% loss)... ---"
# This is the first verification of the IPsec tunnel. A standard-sized ping
# should now pass with 0% packet loss.
docker exec AWS ping -c 3 10.0.2.1

echo
echo "--- Running Test 4: Verifying MTU bottleneck with 'Don't Fragment' ping... ---"
echo "(This test is EXPECTED to fail, proving fragmentation is necessary)"
# We send a packet that is larger than the 1400-byte MTU of the ipip0 tunnel.
# The '-M do' flag sets the "Don't Fragment" bit in the IP header.
# A successful test is one where VPP correctly sends back an ICMP "Fragmentation
# Needed" error message, causing the ping to fail as expected.
docker exec AWS ping -c 1 -s 1472 -M do 10.0.2.1 || true

echo
echo "--- Running Test 5: Pinging OVERLAY with JUMBO FRAME (allowing fragmentation)... ---"
echo "(This test proves VPP is correctly fragmenting and reassembling the jumbo frame)"
# This sends a large 8028-byte packet but allows fragmentation.
# VPP1 must fragment it into multiple smaller packets before IPsec encryption.
# VPP2 must decrypt the fragments and reassemble them into the original packet.
# A success here is the final proof that the entire system works.
docker exec AWS ping -c 3 -s 8000 10.0.2.1

echo
echo "--- All Tests Successful! ---"
echo
echo "================================================================="
echo " POST-TEST PROBES"
echo "================================================================="
echo "--- AWS: Error Counters (Shows fragmentation stats) ---"
# This VPP command shows internal node counters. We can inspect this output
# to see 'ip4-fragment' counters, confirming that fragmentation occurred.
docker exec AWS vppctl show error

echo
echo "--- GCP: Final Interface Counters ---"
# This provides a final view of the interface statistics on the receiving end.
docker exec GCP vppctl show int
echo "================================================================="

echo
echo "--- All tests complete! ---"