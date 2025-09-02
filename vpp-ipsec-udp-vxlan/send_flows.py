#!/usr/bin/env python3
#
# send_flows.py
#
# This script uses scapy to craft a sample Netflow v5 packet, encapsulate it
# in a VXLAN header, and send it to the aws_vpp container to simulate
# traffic from an AWS Traffic Mirroring source.

import time
from scapy.all import *

# --- Configuration ---
# The underlay IP of the aws_vpp container.
AWS_VPP_IP = "192.168.1.2"
# The VNI must match the 'create vxlan tunnel' command in aws-config.sh.
VXLAN_VNI = 100
# The destination port for VXLAN traffic.
VXLAN_PORT = 4789

# This is the "real" source IP of the original flow.
# We are simulating a Netflow exporter at this address.
ORIGINAL_SRC_IP = "10.1.1.1"
# This is a dummy destination IP that the VPP NAT rule is configured to match.
DUMMY_DST_IP = "10.10.10.10"
# The destination port for the Netflow data.
NETFLOW_PORT = 2055

# --- 1. Craft the Inner Packet (Sample Netflow v5) ---
# This is the original packet that AWS Traffic Mirroring would capture.
netflow_header = b""
netflow_header += b"\x00\x05"  # Version 5
netflow_header += b"\x00\x01"  # Flow Record Count (1)
netflow_header += b"\x00\x00\x00\x00" * 5 # Timestamps and sequence
netflow_header += b"\x00\x00\x00\x00" # Engine and sampling

netflow_record = b""
netflow_record += inet_aton("10.1.1.1")  # srcaddr
netflow_record += inet_aton("10.2.2.2")  # dstaddr
netflow_record += b"\x00" * 28 # Other fields
netflow_record += b"\x06"  # prot (TCP)
netflow_record += b"\x00" * 7  # Padding

netflow_payload = netflow_header + netflow_record
# The inner packet has the original source and the dummy destination.
inner_packet = IP(src=ORIGINAL_SRC_IP, dst=DUMMY_DST_IP) / UDP(sport=RandShort(), dport=NETFLOW_PORT) / Raw(load=netflow_payload)

# --- 2. Craft the Outer Packet (VXLAN Encapsulation) ---
# The inner packet is now the payload for the VXLAN header.
# Scapy's VXLAN() layer handles the encapsulation.
vxlan_packet = IP(dst=AWS_VPP_IP) / \
               UDP(sport=RandShort(), dport=VXLAN_PORT) / \
               VXLAN(vni=VXLAN_VNI) / \
               inner_packet

# --- 3. Send the packet ---
print(f"Sending VXLAN-encapsulated Netflow packet to {AWS_VPP_IP}:{VXLAN_PORT}")
print(f"  - VNI: {VXLAN_VNI}")
print(f"  - Inner Packet: {ORIGINAL_SRC_IP} -> {DUMMY_DST_IP}:{NETFLOW_PORT}")
print("Press Ctrl+C to stop.")

try:
    while True:
        send(vxlan_packet, verbose=0)
        print(".", end="", flush=True)
        time.sleep(1)
except KeyboardInterrupt:
    print("\nStopping.")