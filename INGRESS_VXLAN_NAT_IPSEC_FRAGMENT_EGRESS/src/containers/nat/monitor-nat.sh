#!/bin/bash
# NAT Container Monitoring Script - The Address Transformer's Tale

echo "=== 🔄 NAT Container Deep Monitoring - The Address Transformer's Story ==="
echo "📖 Chapter: Network Address Translation Chronicles"
echo "⏰ Timestamp: $(date)"
echo "🎭 Protagonist: chain-nat container"
echo

# Colors for storytelling
GREEN='\033[0;32m'
BLUE='\033[0;34m'  
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Scene 1: The NAT's Identity and Purpose ===${NC}"
echo "🎯 Mission: Transform private addresses (10.10.10.10:2055) to public (10.0.3.1:2055)"
echo "📍 Location: Between VXLAN (10.1.2.2) and IPsec (10.1.3.1) containers"

# Container health
container_status=$(docker inspect chain-nat --format "{{.State.Status}}" 2>/dev/null || echo "missing")
uptime=$(docker inspect chain-nat --format "{{.State.StartedAt}}" 2>/dev/null | xargs -I {} date -d {} '+%s' || echo "0")
now=$(date +%s)
duration=$((now - uptime))

echo -e "${GREEN}📊 Container Status: $container_status${NC}"
echo -e "${GREEN}⏱️  Runtime Duration: ${duration} seconds${NC}"

echo -e "\n${BLUE}=== Scene 2: The NAT's Interfaces - Communication Channels ===${NC}"
# Interface statistics with storytelling
interfaces=$(docker exec chain-nat vppctl show interface 2>/dev/null || echo "No interfaces found")
echo "🔌 Interface Configuration and Statistics:"
echo "$interfaces" | while IFS= read -r line; do
    if [[ "$line" =~ host-eth ]]; then
        echo -e "${GREEN}  📡 $line${NC}"
    elif [[ "$line" =~ "rx packets" ]]; then
        rx_count=$(echo "$line" | awk '{print $3}')
        echo -e "${YELLOW}    📥 Received: $rx_count packets (incoming story chapters)${NC}"
    elif [[ "$line" =~ "tx packets" ]]; then
        tx_count=$(echo "$line" | awk '{print $3}')  
        echo -e "${YELLOW}    📤 Transmitted: $tx_count packets (outgoing transformed stories)${NC}"
    elif [[ "$line" =~ "drops" ]]; then
        echo -e "${RED}    💀 $line (lost stories)${NC}"
    fi
done

echo -e "\n${BLUE}=== Scene 3: NAT Configuration - The Translation Rules ===${NC}"
# NAT address pool
nat_addresses=$(docker exec chain-nat vppctl show nat44 addresses 2>/dev/null || echo "No address pool configured")
echo "🏊 Address Pool (The NAT's arsenal of public identities):"
if [[ "$nat_addresses" != "No address pool configured" ]]; then
    echo -e "${GREEN}$nat_addresses${NC}"
else
    echo -e "${RED}❌ No NAT address pool found - The transformer has no disguises!${NC}"
fi

# NAT interfaces
echo -e "\n🔗 Interface Roles:"
nat_interfaces=$(docker exec chain-nat vppctl show nat44 interfaces 2>/dev/null || echo "No interfaces configured")
if [[ "$nat_interfaces" != "No interfaces configured" ]]; then
    echo -e "${GREEN}$nat_interfaces${NC}"
else
    echo -e "${RED}❌ No NAT interfaces configured - The transformer doesn't know its role!${NC}"
fi

echo -e "\n${BLUE}=== Scene 4: Active NAT Sessions - Current Transformations ===${NC}"
# Current NAT sessions  
nat_sessions=$(docker exec chain-nat vppctl show nat44 sessions 2>/dev/null || echo "No active sessions")
session_count=$(echo "$nat_sessions" | grep -c "tcp\|udp\|icmp" 2>/dev/null || echo "0")
echo "🎭 Active Translation Sessions: $session_count"

if [[ "$nat_sessions" != "No active sessions" ]] && [[ "$session_count" -gt 0 ]]; then
    echo -e "${GREEN}📋 Current Address Transformations:${NC}"
    echo "$nat_sessions" | head -10
    
    # Analyze session types
    udp_sessions=$(echo "$nat_sessions" | grep -c "udp" 2>/dev/null || echo "0")
    tcp_sessions=$(echo "$nat_sessions" | grep -c "tcp" 2>/dev/null || echo "0") 
    icmp_sessions=$(echo "$nat_sessions" | grep -c "icmp" 2>/dev/null || echo "0")
    
    echo -e "\n📊 Session Distribution:"
    echo -e "${YELLOW}  🔄 UDP Sessions: $udp_sessions (our main story - VXLAN payload)${NC}"
    echo -e "${YELLOW}  🔄 TCP Sessions: $tcp_sessions${NC}"
    echo -e "${YELLOW}  🔄 ICMP Sessions: $icmp_sessions${NC}"
else
    echo -e "${YELLOW}⚠️  No active translation sessions - The transformer is idle${NC}"
fi

echo -e "\n${BLUE}=== Scene 5: NAT Statistics - Performance Metrics ===${NC}"
# NAT counters and statistics
nat_stats=$(docker exec chain-nat vppctl show nat44 statistics 2>/dev/null || echo "No statistics available")
if [[ "$nat_stats" != "No statistics available" ]]; then
    echo -e "${GREEN}📈 Translation Statistics:${NC}"
    echo "$nat_stats"
else
    echo -e "${YELLOW}⚠️  No NAT statistics available${NC}"
fi

# Memory usage
echo -e "\n💾 Memory Usage:"
memory_info=$(docker exec chain-nat vppctl show memory | head -5 2>/dev/null || echo "Memory info unavailable")
echo -e "${BLUE}$memory_info${NC}"

echo -e "\n${BLUE}=== Scene 6: Packet Traces - The NAT's Recent Actions ===${NC}"
# Recent packet traces
echo "🔍 Recent packet transformations:"
docker exec chain-nat vppctl clear trace >/dev/null 2>&1 || true
sleep 1
traces=$(docker exec chain-nat vppctl show trace 2>/dev/null || echo "No traces available")

if [[ "$traces" != "No traces available" ]]; then
    echo -e "${GREEN}📝 Packet Processing Traces:${NC}"
    echo "$traces" | head -20
else
    echo -e "${YELLOW}⚠️  No recent packet traces - Enable tracing to see the action${NC}"
    echo "💡 To enable: docker exec chain-nat vppctl trace add nat44-ed-in2out 50"
fi

echo -e "\n${BLUE}=== Scene 7: Error Analysis - Troubleshooting the Transformer ===${NC}"
# Error counters
errors=$(docker exec chain-nat vppctl show errors 2>/dev/null | head -10 || echo "No error information")
if [[ "$errors" != "No error information" ]]; then
    echo -e "${RED}⚠️  Error Counters:${NC}"
    echo "$errors"
else
    echo -e "${GREEN}✅ No errors detected - The transformer is operating smoothly${NC}"
fi

# Runtime information
echo -e "\n⚡ Runtime Performance:"
runtime=$(docker exec chain-nat vppctl show runtime | head -10 2>/dev/null || echo "Runtime info unavailable")
echo -e "${BLUE}$runtime${NC}"

echo -e "\n${BLUE}=== Epilogue: NAT Container Health Summary ===${NC}"
if [[ "$container_status" == "running" ]] && [[ "$session_count" -gt 0 ]]; then
    echo -e "${GREEN}🎉 SUCCESS: NAT container is actively transforming addresses${NC}"
    echo -e "${GREEN}📈 Performance: $session_count active translations${NC}"
elif [[ "$container_status" == "running" ]]; then
    echo -e "${YELLOW}⚠️  WARNING: NAT container is running but idle (no active sessions)${NC}"
else
    echo -e "${RED}❌ ERROR: NAT container is not functioning properly${NC}"
fi

echo -e "\n📚 End of NAT Container Story - Chapter Complete"
echo "==============================================="