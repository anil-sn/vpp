#!/bin/bash
# Packet analysis script for GCP endpoint container

CAPTURE_FILE=${1:-/tmp/gcp-received.pcap}

if [ ! -f "$CAPTURE_FILE" ]; then
    echo "Error: Capture file $CAPTURE_FILE not found"
    exit 1
fi

echo "=== GCP Packet Analysis ==="
echo "File: $CAPTURE_FILE"
echo "Timestamp: $(date)"
echo

# Basic packet statistics
echo "--- Packet Summary ---"
tcpdump -r $CAPTURE_FILE -nn 2>&1 | tail -5

# Protocol distribution
echo -e "\n--- Protocol Distribution ---"
tcpdump -r $CAPTURE_FILE -nn 2>/dev/null | \
    awk '{print $3}' | cut -d. -f5 | sort | uniq -c | sort -nr

# Source/destination analysis
echo -e "\n--- Traffic Flow ---"
tcpdump -r $CAPTURE_FILE -nn 2>/dev/null | \
    awk '{print $3 " -> " $5}' | head -10

# Fragment analysis
echo -e "\n--- Fragment Analysis ---"
tcpdump -r $CAPTURE_FILE -nn 2>/dev/null | grep -i frag | head -5

# UDP traffic analysis (for VXLAN)
echo -e "\n--- UDP Traffic ---"
tcpdump -r $CAPTURE_FILE -nn udp 2>/dev/null | head -5

# Size analysis
echo -e "\n--- Packet Sizes ---"
tcpdump -r $CAPTURE_FILE -nn 2>/dev/null | \
    grep -o 'length [0-9]*' | cut -d' ' -f2 | sort -n | uniq -c

echo -e "\n=== End Analysis ==="