#!/bin/bash
# VXLAN Container Monitoring Script - The Tunnel Master's Chronicles

echo "=== 📦 VXLAN Container Deep Monitoring - The Tunnel Master's Tale ==="
echo "📖 Chapter: VXLAN Decapsulation Chronicles"
echo "⏰ Timestamp: $(date)"
echo "🎭 Protagonist: chain-vxlan container"
echo

# Colors for storytelling
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}=== Scene 1: The VXLAN Master's Identity ===${NC}"
echo "🎯 Mission: Unwrap VXLAN packets (VNI 100) and forward inner payloads"
echo "📍 Location: Between Ingress (10.1.1.1) and NAT (10.1.2.1) containers"
echo "🔧 Specialty: Layer 2 over Layer 3 tunneling magic"

# Container health
container_status=$(docker inspect chain-vxlan --format "{{.State.Status}}" 2>/dev/null || echo "missing")
uptime=$(docker inspect chain-vxlan --format "{{.State.StartedAt}}" 2>/dev/null | xargs -I {} date -d {} '+%s' || echo "0")
now=$(date +%s)
duration=$((now - uptime))

echo -e "${GREEN}📊 Container Status: $container_status${NC}"
echo -e "${GREEN}⏱️  Runtime Duration: ${duration} seconds${NC}"

echo -e "\n${BLUE}=== Scene 2: The Tunnel Master's Interfaces ===${NC}"
# Interface analysis with storytelling
echo "🔌 Network Interface Status:"
interfaces=$(docker exec chain-vxlan vppctl show interface 2>/dev/null || echo "No interfaces found")

echo "$interfaces" | while IFS= read -r line; do
    if [[ "$line" =~ host-eth0 ]]; then
        echo -e "${GREEN}  📡 host-eth0 (Entrance): $line${NC}"
    elif [[ "$line" =~ host-eth1 ]]; then
        echo -e "${GREEN}  📡 host-eth1 (Exit): $line${NC}"
    elif [[ "$line" =~ vxlan_tunnel ]]; then
        echo -e "${PURPLE}  🚇 VXLAN Tunnel: $line${NC}"
    elif [[ "$line" =~ "rx packets" ]]; then
        rx_count=$(echo "$line" | awk '{print $3}')
        echo -e "${YELLOW}    📥 Received: $rx_count packets (VXLAN capsules arriving)${NC}"
    elif [[ "$line" =~ "tx packets" ]]; then
        tx_count=$(echo "$line" | awk '{print $3}')
        echo -e "${YELLOW}    📤 Transmitted: $tx_count packets (unwrapped contents departing)${NC}"
    elif [[ "$line" =~ "drops" ]]; then
        echo -e "${RED}    💀 $line (lost in the tunnel)${NC}"
    fi
done

echo -e "\n${BLUE}=== Scene 3: VXLAN Tunnel Configuration ===${NC}"
# VXLAN tunnel status
vxlan_tunnels=$(docker exec chain-vxlan vppctl show vxlan tunnel 2>/dev/null || echo "No tunnels configured")
tunnel_count=$(echo "$vxlan_tunnels" | grep -c "vxlan_tunnel" 2>/dev/null || echo "0")

echo "🚇 VXLAN Tunnel Inventory: $tunnel_count tunnels"
if [[ "$vxlan_tunnels" != "No tunnels configured" ]] && [[ "$tunnel_count" -gt 0 ]]; then
    echo -e "${GREEN}📋 Tunnel Configuration:${NC}"
    echo "$vxlan_tunnels" | while IFS= read -r line; do
        if [[ "$line" =~ vxlan_tunnel ]]; then
            tunnel_id=$(echo "$line" | awk '{print $1}' | sed 's/\[//' | sed 's/\]//')
            echo -e "${PURPLE}  🚇 Tunnel $tunnel_id: $line${NC}"
        elif [[ "$line" =~ "src" ]] || [[ "$line" =~ "dst" ]] || [[ "$line" =~ "vni" ]]; then
            echo -e "${BLUE}    $line${NC}"
        fi
    done
    
    # VNI analysis
    vni_100_found=$(echo "$vxlan_tunnels" | grep -c "vni 100" || echo "0")
    if [[ "$vni_100_found" -gt 0 ]]; then
        echo -e "${GREEN}✅ VNI 100 tunnel found - Ready for our specific traffic${NC}"
    else
        echo -e "${RED}❌ VNI 100 tunnel not found - Missing our designated tunnel!${NC}"
    fi
else
    echo -e "${RED}❌ No VXLAN tunnels configured - The tunnel master has no tunnels!${NC}"
fi

echo -e "\n${BLUE}=== Scene 4: Bridge Domain Configuration ===${NC}"
# Bridge domain information
bridge_domains=$(docker exec chain-vxlan vppctl show bridge-domain 2>/dev/null || echo "No bridge domains")
if [[ "$bridge_domains" != "No bridge domains" ]]; then
    echo -e "${GREEN}🌉 Bridge Domains (L2 learning spaces):${NC}"
    echo "$bridge_domains"
else
    echo -e "${YELLOW}⚠️  No bridge domains configured - Using L3 routing only${NC}"
fi

# L2 FIB (forwarding table)
echo -e "\n📚 L2 Forwarding Information Base:"
l2_fib=$(docker exec chain-vxlan vppctl show l2fib verbose 2>/dev/null || echo "No L2 FIB entries")
if [[ "$l2_fib" != "No L2 FIB entries" ]]; then
    echo -e "${GREEN}$l2_fib${NC}"
else
    echo -e "${YELLOW}⚠️  No L2 FIB entries - Learning table is empty${NC}"
fi

echo -e "\n${BLUE}=== Scene 5: VXLAN Processing Statistics ===${NC}"
# VXLAN-specific statistics
echo "📊 VXLAN Processing Metrics:"

# Check for VXLAN-specific counters
vxlan_stats=$(docker exec chain-vxlan vppctl show vxlan statistics 2>/dev/null || echo "No VXLAN statistics")
if [[ "$vxlan_stats" != "No VXLAN statistics" ]]; then
    echo -e "${GREEN}$vxlan_stats${NC}"
fi

# UDP statistics (VXLAN uses UDP port 4789)
echo -e "\n🌐 UDP Statistics (VXLAN transport):"
udp_stats=$(docker exec chain-vxlan vppctl show udp 2>/dev/null || echo "No UDP statistics")
if [[ "$udp_stats" != "No UDP statistics" ]]; then
    echo -e "${BLUE}$udp_stats${NC}"
    
    # Look for port 4789 specifically
    port_4789_info=$(echo "$udp_stats" | grep "4789" || echo "Port 4789 not found in statistics")
    if [[ "$port_4789_info" != "Port 4789 not found in statistics" ]]; then
        echo -e "${GREEN}✅ VXLAN port 4789 active: $port_4789_info${NC}"
    else
        echo -e "${YELLOW}⚠️  VXLAN port 4789 not found in UDP statistics${NC}"
    fi
fi

echo -e "\n${BLUE}=== Scene 6: Packet Flow Analysis ===${NC}"
# Recent packet traces
echo "🔍 Recent VXLAN packet processing:"
docker exec chain-vxlan vppctl clear trace >/dev/null 2>&1 || true

# Enable VXLAN tracing
docker exec chain-vxlan vppctl trace add vxlan-input 20 >/dev/null 2>&1 || true
docker exec chain-vxlan vppctl trace add vxlan4-decap 20 >/dev/null 2>&1 || true
sleep 1

traces=$(docker exec chain-vxlan vppctl show trace 2>/dev/null || echo "No traces available")
if [[ "$traces" != "No traces available" ]]; then
    echo -e "${GREEN}📝 VXLAN Packet Traces:${NC}"
    echo "$traces" | head -25
    
    # Analyze trace content
    decap_count=$(echo "$traces" | grep -c "vxlan.*decap" || echo "0")
    encap_count=$(echo "$traces" | grep -c "vxlan.*encap" || echo "0")
    
    echo -e "\n📊 Trace Analysis:"
    echo -e "${YELLOW}  📦 Decapsulation events: $decap_count${NC}"
    echo -e "${YELLOW}  📦 Encapsulation events: $encap_count${NC}"
else
    echo -e "${YELLOW}⚠️  No packet traces available${NC}"
    echo "💡 To enable: docker exec chain-vxlan vppctl trace add vxlan-input 50"
fi

echo -e "\n${BLUE}=== Scene 7: Memory and Performance ===${NC}"
# Memory usage
echo "💾 Memory Utilization:"
memory_info=$(docker exec chain-vxlan vppctl show memory | head -5 2>/dev/null || echo "Memory info unavailable")
echo -e "${BLUE}$memory_info${NC}"

# Runtime performance
echo -e "\n⚡ Runtime Performance:"
runtime=$(docker exec chain-vxlan vppctl show runtime | grep -E "(vxlan|l2|bridge)" | head -10 2>/dev/null || echo "No VXLAN runtime info")
if [[ "$runtime" != "No VXLAN runtime info" ]]; then
    echo -e "${BLUE}$runtime${NC}"
fi

echo -e "\n${BLUE}=== Scene 8: Error Analysis ===${NC}"
# Error analysis
errors=$(docker exec chain-vxlan vppctl show errors | grep -v " 0 " | head -10 2>/dev/null || echo "No errors")
if [[ "$errors" != "No errors" ]]; then
    echo -e "${RED}⚠️  Active Error Counters:${NC}"
    echo "$errors"
else
    echo -e "${GREEN}✅ No active errors - Tunnel operations are clean${NC}"
fi

echo -e "\n${BLUE}=== Epilogue: VXLAN Container Health Summary ===${NC}"
# Health assessment
if [[ "$container_status" == "running" ]] && [[ "$tunnel_count" -gt 0 ]]; then
    echo -e "${GREEN}🎉 SUCCESS: VXLAN tunnel master is operational${NC}"
    echo -e "${GREEN}🚇 Tunnels: $tunnel_count active tunnels${NC}"
    
    # Check for traffic indicators
    total_rx=$(echo "$interfaces" | grep "rx packets" | head -1 | awk '{print $3}' || echo "0")
    total_tx=$(echo "$interfaces" | grep "tx packets" | head -1 | awk '{print $3}' || echo "0")
    
    if [[ "$total_rx" -gt 0 ]] && [[ "$total_tx" -gt 0 ]]; then
        echo -e "${GREEN}📊 Traffic: Active processing (RX: $total_rx, TX: $total_tx)${NC}"
    elif [[ "$total_rx" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Traffic: Receiving but not forwarding (check downstream)${NC}"
    else
        echo -e "${YELLOW}⚠️  Traffic: No packets processed yet${NC}"
    fi
elif [[ "$container_status" == "running" ]]; then
    echo -e "${YELLOW}⚠️  WARNING: Container running but no tunnels configured${NC}"
else
    echo -e "${RED}❌ ERROR: VXLAN container is not functioning${NC}"
fi

echo -e "\n📚 End of VXLAN Container Story - Chapter Complete"
echo "=================================================="