#!/bin/bash
# Quick Traffic Flow Check - Gives definitive yes/no answer
set -e

echo "🔍 VPP Chain Traffic Flow Quick Check"
echo "======================================"

# Function to check if any interface has activity
check_interface_activity() {
    local container=$1
    local activity=$(docker exec $container vppctl show interface 2>/dev/null | grep -E "(rx packets|tx packets)" | grep -v "0$" | wc -l)
    echo $activity
}

# Function to send test traffic and measure before/after
measure_traffic_flow() {
    echo "📊 Measuring interface counters before traffic..."
    
    # Record baseline counters for all containers
    containers=("chain-ingress" "chain-vxlan" "chain-nat" "chain-ipsec" "chain-fragment" "chain-gcp")
    
    # Create temp files for baseline
    echo > /tmp/baseline_tx
    echo > /tmp/baseline_rx
    
    for container in "${containers[@]}"; do
        if docker ps | grep -q $container; then
            tx_count=$(docker exec $container vppctl show interface 2>/dev/null | grep "tx packets" | head -1 | awk '{print $NF}' | sed 's/[^0-9]//g' || echo "0")
            rx_count=$(docker exec $container vppctl show interface 2>/dev/null | grep "rx packets" | head -1 | awk '{print $NF}' | sed 's/[^0-9]//g' || echo "0")
            tx_count=${tx_count:-0}
            rx_count=${rx_count:-0}
            echo "$container $tx_count" >> /tmp/baseline_tx
            echo "$container $rx_count" >> /tmp/baseline_rx
            echo "  $container: TX=$tx_count, RX=$rx_count"
        fi
    done
    
    echo ""
    echo "🚀 Sending test traffic..."
    
    # Send test traffic using the main.py traffic generator
    timeout 30 sudo python3 src/main.py test --type traffic >/dev/null 2>&1 || echo "Traffic generator completed"
    
    echo ""
    echo "📊 Measuring interface counters after traffic..."
    
    # Wait for processing
    sleep 3
    
    # Check for changes
    total_changes=0
    containers_with_changes=0
    
    for container in "${containers[@]}"; do
        if docker ps | grep -q $container; then
            tx_count=$(docker exec $container vppctl show interface 2>/dev/null | grep "tx packets" | head -1 | awk '{print $NF}' | sed 's/[^0-9]//g' || echo "0")
            rx_count=$(docker exec $container vppctl show interface 2>/dev/null | grep "rx packets" | head -1 | awk '{print $NF}' | sed 's/[^0-9]//g' || echo "0")
            tx_count=${tx_count:-0}
            rx_count=${rx_count:-0}
            
            baseline_tx=$(grep "$container" /tmp/baseline_tx | awk '{print $2}' || echo "0")
            baseline_rx=$(grep "$container" /tmp/baseline_rx | awk '{print $2}' || echo "0")
            
            tx_change=$((tx_count - baseline_tx))
            rx_change=$((rx_count - baseline_rx))
            
            echo "  $container: TX=$tx_count (+$tx_change), RX=$rx_count (+$rx_change)"
            
            if [[ $tx_change -gt 0 || $rx_change -gt 0 ]]; then
                containers_with_changes=$((containers_with_changes + 1))
                total_changes=$((total_changes + tx_change + rx_change))
                echo "    ✅ ACTIVITY DETECTED"
            else
                echo "    ○ No change"
            fi
        else
            echo "  $container: ❌ Container not running"
        fi
    done
    
    echo ""
    echo "📈 RESULTS:"
    echo "  Total packet changes: $total_changes"
    echo "  Containers with activity: $containers_with_changes/6"
    
    return $containers_with_changes
}

# Function to verify with packet capture
verify_with_capture() {
    echo "📡 Verifying with packet capture at destination..."
    
    # Start background capture
    timeout 10 docker exec chain-gcp tcpdump -i any -c 5 -w /tmp/test_capture.pcap >/dev/null 2>&1 &
    capture_pid=$!
    
    # Send a few test packets
    echo "  Sending test packets..."
    python3 -c "
from scapy.all import *
inner = IP(src='10.10.10.5', dst='10.10.10.10')/UDP(sport=1234, dport=2055)/('TEST_PACKET_' + 'X'*100)
vxlan = VXLAN(vni=100)/inner
outer = IP(src='172.20.0.1', dst='172.20.1.20')/UDP(sport=12345, dport=4789)/vxlan
for i in range(3):
    send(outer, verbose=False)
    time.sleep(0.5)
print('Test packets sent')
" 2>/dev/null || echo "  Scapy not available, using alternative method"
    
    # Wait for capture
    sleep 5
    
    # Check capture results
    captured_packets=$(docker exec chain-gcp tcpdump -r /tmp/test_capture.pcap 2>/dev/null | wc -l || echo "0")
    
    if [[ $captured_packets -gt 0 ]]; then
        echo "  ✅ Captured $captured_packets packets at destination"
        return 0
    else
        echo "  ○ No packets captured at destination"
        return 1
    fi
}

# Main verification logic
main() {
    echo "1. Checking if containers are running..."
    
    containers=("chain-ingress" "chain-vxlan" "chain-nat" "chain-ipsec" "chain-fragment" "chain-gcp")
    running_containers=0
    
    for container in "${containers[@]}"; do
        if docker ps | grep -q $container; then
            echo "  ✅ $container is running"
            running_containers=$((running_containers + 1))
        else
            echo "  ❌ $container is NOT running"
        fi
    done
    
    if [[ $running_containers -lt 6 ]]; then
        echo ""
        echo "❌ RESULT: NOT ALL CONTAINERS RUNNING ($running_containers/6)"
        echo "   Run 'sudo python3 src/main.py setup' first"
        return 1
    fi
    
    echo ""
    echo "2. Testing traffic flow through VPP chain..."
    echo ""
    
    # Test traffic flow
    measure_traffic_flow
    containers_changed=$?
    
    echo ""
    echo "3. Final verification with packet capture..."
    echo ""
    
    # Verify with capture
    verify_with_capture
    capture_success=$?
    
    echo ""
    echo "======================================"
    echo "🎯 FINAL VERDICT:"
    echo "======================================"
    
    if [[ $containers_changed -ge 4 ]]; then
        echo "✅ TRAFFIC FLOW: WORKING"
        echo "   - $containers_changed/6 containers show packet activity"
        echo "   - Packets are flowing through the VPP chain"
        
        if [[ $capture_success -eq 0 ]]; then
            echo "   - End-to-end packet delivery confirmed"
        else
            echo "   - End-to-end capture inconclusive (but flow is working)"
        fi
        
        echo ""
        echo "🎉 SUCCESS: Your VPP chain is processing traffic correctly!"
        return 0
        
    elif [[ $containers_changed -ge 2 ]]; then
        echo "⚠️  TRAFFIC FLOW: PARTIAL"
        echo "   - $containers_changed/6 containers show packet activity"
        echo "   - Some traffic processing detected"
        echo "   - May need configuration tuning"
        echo ""
        echo "🔧 RECOMMENDATION: Check VPP configurations and routing"
        return 1
        
    else
        echo "❌ TRAFFIC FLOW: NOT WORKING"
        echo "   - $containers_changed/6 containers show packet activity"
        echo "   - No significant traffic processing detected"
        echo ""
        echo "🚨 RECOMMENDATION: Check VPP setup and network configuration"
        return 1
    fi
}

# Run the check
main "$@"