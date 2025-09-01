#!/usr/bin/env python3
#
# send_flows.py
#
# This script uses scapy to craft and send sample Netflow v5 and sFlow packets
# to a collector IP address. This simulates a router or switch exporting flow data.

import time
from scapy.all import *

# Define the destination IP (the GCP application) and source IP (the AWS application)
COLLECTOR_IP = "10.0.2.1"
EXPORTER_IP = "10.0.1.1"

# Standard UDP ports for Netflow and sFlow
NETFLOW_PORT = 2055
SFLOW_PORT = 6343

# --- 1. Craft a sample Netflow v5 Packet ---
# Netflow v5 has a fixed 24-byte header and up to 30 flow records of 48 bytes each.
# We will create a header and one sample flow record.

# Netflow v5 Header
netflow_header = b""
netflow_header += b"\x00\x05"  # Version 5
netflow_header += b"\x00\x01"  # Flow Record Count (1)
netflow_header += b"\x00\x00\x00\x00"  # sysUpTime
netflow_header += b"\x00\x00\x00\x00"  # unix_secs
netflow_header += b"\x00\x00\x00\x00"  # unix_nsecs
netflow_header += b"\x00\x00\x00\x00"  # flow_sequence
netflow_header += b"\x00"  # engine_type
netflow_header += b"\x00"  # engine_id
netflow_header += b"\x00\x00"  # sampling_interval

# A single Netflow v5 Flow Record (simulating a TCP connection)
netflow_record = b""
netflow_record += inet_aton("10.1.1.1")  # srcaddr
netflow_record += inet_aton("10.2.2.2")  # dstaddr
netflow_record += b"\x00\x00\x00\x00"  # nexthop
netflow_record += b"\x00\x00"  # input
netflow_record += b"\x00\x00"  # output
netflow_record += b"\x00\x00\x10\x00"  # dPkts (4096)
netflow_record += b"\x00\x10\x00\x00"  # dOctets (1MB)
netflow_record += b"\x00\x00\x00\x00"  # First
netflow_record += b"\x00\x00\x00\x00"  # Last
netflow_record += b"\x17\x70"  # srcport (6000)
netflow_record += b"\x00\x50"  # dstport (80)
netflow_record += b"\x00"  # pad1
netflow_record += b"\x06"  # prot (TCP)
netflow_record += b"\x00"  # tos
netflow_record += b"\x06"  # tcp_flags (SYN-ACK)
netflow_record += b"\x00\x00\x00\x00\x00\x00"  # pad2 & reserved

# Combine header and record
netflow_payload = netflow_header + netflow_record
netflow_packet = IP(src=EXPORTER_IP, dst=COLLECTOR_IP) / UDP(sport=RandShort(), dport=NETFLOW_PORT) / Raw(load=netflow_payload)


# --- 2. Craft a sample sFlow Packet ---
# sFlow is more complex. We will simulate a simple datagram with one flow sample.
# This is a simplified representation for transport testing.
sflow_payload = b""
sflow_payload += b"\x00\x00\x00\x05" # sFlow version 5
sflow_payload += b"\x00\x00\x00\x01" # IP version (IPv4)
sflow_payload += b"\x00\x01\x02\x03" # Agent Sub-ID
sflow_payload += b"\x00\x00\x00\x01" # Sequence Number
sflow_payload += b"\x00\x00\x00\x00" # Uptime
sflow_payload += b"\x00\x00\x00\x01" # Number of samples (1)
# ... plus a sample record (simplified)
sflow_payload += b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f"

sflow_packet = IP(src=EXPORTER_IP, dst=COLLECTOR_IP) / UDP(sport=RandShort(), dport=SFLOW_PORT) / Raw(load=sflow_payload)


# --- 3. Send the packets ---
print(f"Sending Netflow and sFlow packets from {EXPORTER_IP} to {COLLECTOR_IP}...")
print("Press Ctrl+C to stop.")

try:
    while True:
        send(netflow_packet, verbose=0)
        send(sflow_packet, verbose=0)
        print(".", end="", flush=True)
        time.sleep(1)
except KeyboardInterrupt:
    print("\nStopping.")