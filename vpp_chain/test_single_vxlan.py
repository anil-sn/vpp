#!/usr/bin/env python3
"""
Quick VXLAN test to debug L2/L3 forwarding issue
"""

import time
from scapy.all import *

# Get the bridge interface (same as in traffic generator)
bridge_interface = "br-77343d7af5b6"

print(f"Sending single VXLAN test packet via {bridge_interface}")

# Create a single VXLAN packet
outer_ip = IP(src="172.20.100.1", dst="172.20.100.10")
outer_udp = UDP(sport=12345, dport=4789)
vxlan_header = VXLAN(vni=100, flags="Instance")
inner_eth = Ether(src="00:00:40:11:4d:36", dst="02:fe:1b:2f:30:d4")
inner_ip = IP(src="10.10.10.5", dst="10.10.10.10")
inner_udp = UDP(sport=45678, dport=2055)
payload = Raw("A" * 100)  # Small payload

# Build complete packet (Ethernet + IP + UDP + VXLAN + inner frame)
outer_eth = Ether()  # This will be set by sendp()
packet = outer_eth / outer_ip / outer_udp / vxlan_header / inner_eth / inner_ip / inner_udp / payload

print(f"Packet size: {len(packet)} bytes")
print(f"VXLAN VNI: 100")
print(f"Inner traffic: {inner_ip.src} -> {inner_ip.dst}:{inner_udp.dport}")

# Set correct MAC addresses for VPP interface
packet[Ether].src = "f6:f9:91:78:31:ad"  # Bridge MAC
packet[Ether].dst = "02:fe:0c:c5:ea:a0"   # VPP interface MAC

# Send packet
sendp(packet, iface=bridge_interface, verbose=True)
print("Packet sent. Check VPP traces with: docker exec vxlan-processor vppctl show trace")