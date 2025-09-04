#!/bin/bash
# Performance monitoring script for VPP Multi-Container Chain

set -e

echo "========================================"
echo "VPP Multi-Container Chain Performance Monitor"
echo "========================================"

# Duration for monitoring (default 60 seconds)
DURATION=${1:-60}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

info "Monitoring for $DURATION seconds..."

# Check if containers are running
containers=("chain-ingress" "chain-vxlan" "chain-nat" "chain-ipsec" "chain-fragment" "chain-gcp")
for container in "${containers[@]}"; do
    if ! docker ps | grep -q "$container"; then
        echo "ERROR: $container is not running"
        exit 1
    fi
done

# Create monitoring log directory
mkdir -p /tmp/vpp-performance
timestamp=$(date +%Y%m%d_%H%M%S)
logfile="/tmp/vpp-performance/monitor_${timestamp}.log"

info "Logging to: $logfile"

# Monitor function
monitor_loop() {
    local end_time=$((SECONDS + DURATION))
    local counter=0
    
    echo "Starting performance monitoring..." | tee -a "$logfile"
    echo "Timestamp,Container,CPU%,Memory,RX_Packets,TX_Packets,RX_Bytes,TX_Bytes" | tee -a "$logfile"
    
    while [ $SECONDS -lt $end_time ]; do
        counter=$((counter + 1))
        current_time=$(date '+%H:%M:%S')
        
        # System resources
        echo "" | tee -a "$logfile"
        echo "=== $current_time (Sample $counter) ===" | tee -a "$logfile"
        
        # Docker stats
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep chain- | tee -a "$logfile"
        
        # VPP interface statistics for each container
        for container in "${containers[@]}"; do
            if docker ps | grep -q "$container"; then
                echo "" | tee -a "$logfile"
                echo "--- $container VPP Stats ---" | tee -a "$logfile"
                
                # Interface statistics
                docker exec "$container" vppctl show interface rx-placement 2>/dev/null | tee -a "$logfile" || true
                
                # Hardware statistics
                docker exec "$container" vppctl show hardware-interfaces brief 2>/dev/null | head -10 | tee -a "$logfile" || true
            fi
        done
        
        # System memory and CPU
        echo "" | tee -a "$logfile"
        echo "--- System Resources ---" | tee -a "$logfile"
        echo "Memory: $(free -h | grep ^Mem | awk '{print $3"/"$2}')" | tee -a "$logfile"
        echo "Load: $(cat /proc/loadavg)" | tee -a "$logfile"
        
        # Wait before next sample
        sleep 10
    done
}

# Start monitoring
monitor_loop

echo ""
success "Monitoring complete!"
echo "Performance data saved to: $logfile"

# Generate summary
info "Generating performance summary..."
summary_file="/tmp/vpp-performance/summary_${timestamp}.txt"

cat > "$summary_file" << EOF
VPP Multi-Container Chain Performance Summary
Generated: $(date)
Duration: ${DURATION} seconds

=== Container Status ===
$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" | grep chain-)

=== Final Interface Statistics ===
EOF

for container in "${containers[@]}"; do
    if docker ps | grep -q "$container"; then
        echo "" >> "$summary_file"
        echo "--- $container ---" >> "$summary_file"
        docker exec "$container" vppctl show interface addr >> "$summary_file" 2>/dev/null || true
        docker exec "$container" vppctl show runtime >> "$summary_file" 2>/dev/null || true
    fi
done

success "Summary saved to: $summary_file"

echo ""
echo "Files created:"
echo "  - Detailed log: $logfile"
echo "  - Summary: $summary_file"
echo ""
echo "To analyze performance:"
echo "  tail -f $logfile"
echo "  cat $summary_file"