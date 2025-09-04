#!/bin/bash
# Packet capture script for GCP endpoint container

CAPTURE_FILE=${1:-/tmp/gcp-received.pcap}
INTERFACE=${2:-vpp-tap0}
COUNT=${3:-100}
TIMEOUT=${4:-60}

echo "=== Starting packet capture on GCP endpoint ==="
echo "Interface: $INTERFACE"
echo "Capture file: $CAPTURE_FILE" 
echo "Packet count: $COUNT"
echo "Timeout: ${TIMEOUT}s"
echo "Timestamp: $(date)"
echo

# Start tcpdump in background
timeout $TIMEOUT tcpdump -i $INTERFACE -w $CAPTURE_FILE -c $COUNT &
TCPDUMP_PID=$!

echo "Capture started (PID: $TCPDUMP_PID)"
echo "Waiting for packets..."

# Wait for capture to complete
wait $TCPDUMP_PID
RESULT=$?

if [ $RESULT -eq 0 ]; then
    echo "Capture completed successfully"
    echo "Packets captured: $(tcpdump -r $CAPTURE_FILE 2>&1 | tail -1 | grep -o '[0-9]* packets' | cut -d' ' -f1)"
elif [ $RESULT -eq 124 ]; then
    echo "Capture timed out after ${TIMEOUT}s"
else
    echo "Capture failed with exit code: $RESULT"
fi

echo "Capture file: $CAPTURE_FILE"
echo "=== End packet capture ==="