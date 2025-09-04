#!/bin/bash
# IPsec Container Monitoring Script - The Security Guardian's Chronicle

echo "=== 🔒 IPsec Container Deep Monitoring - The Security Guardian's Tale ==="
echo "📖 Chapter: Cryptographic Protection Chronicles"
echo "⏰ Timestamp: $(date)"
echo "🎭 Protagonist: chain-ipsec container"
echo

# Colors for storytelling
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}=== Scene 1: The Security Guardian's Mission ===${NC}"
echo "🛡️  Mission: Encrypt packets with ESP AES-GCM-128 for secure transport"
echo "📍 Location: Between NAT (10.1.3.2) and Fragment (10.1.4.1) containers"
echo "🔐 Specialty: Military-grade packet encryption and tunnel establishment"

# Container health
container_status=$(docker inspect chain-ipsec --format "{{.State.Status}}" 2>/dev/null || echo "missing")
uptime=$(docker inspect chain-ipsec --format "{{.State.StartedAt}}" 2>/dev/null | xargs -I {} date -d {} '+%s' || echo "0")
now=$(date +%s)
duration=$((now - uptime))

echo -e "${GREEN}📊 Guardian Status: $container_status${NC}"
echo -e "${GREEN}⏱️  On Duty Duration: ${duration} seconds${NC}"

echo -e "\n${BLUE}=== Scene 2: The Guardian's Network Interfaces ===${NC}"
# Interface analysis
echo "🔌 Secure Communication Channels:"
interfaces=$(docker exec chain-ipsec vppctl show interface 2>/dev/null || echo "No interfaces found")

echo "$interfaces" | while IFS= read -r line; do
    if [[ "$line" =~ host-eth0 ]]; then
        echo -e "${GREEN}  📡 host-eth0 (Plaintext In): $line${NC}"
    elif [[ "$line" =~ host-eth1 ]]; then
        echo -e "${GREEN}  📡 host-eth1 (Encrypted Out): $line${NC}"
    elif [[ "$line" =~ ipsec ]]; then
        echo -e "${PURPLE}  🔒 IPsec Tunnel: $line${NC}"
    elif [[ "$line" =~ "rx packets" ]]; then
        rx_count=$(echo "$line" | awk '{print $3}')
        echo -e "${YELLOW}    📥 Received: $rx_count packets (awaiting encryption)${NC}"
    elif [[ "$line" =~ "tx packets" ]]; then
        tx_count=$(echo "$line" | awk '{print $3}')
        echo -e "${YELLOW}    📤 Transmitted: $tx_count packets (secured and sealed)${NC}"
    elif [[ "$line" =~ "drops" ]]; then
        echo -e "${RED}    💀 $line (security breaches - packets lost)${NC}"
    fi
done

echo -e "\n${BLUE}=== Scene 3: Security Associations - The Guardian's Arsenal ===${NC}"
# IPsec Security Associations
ipsec_sa=$(docker exec chain-ipsec vppctl show ipsec sa 2>/dev/null || echo "No Security Associations")
sa_count=$(echo "$ipsec_sa" | grep -c "^\[" 2>/dev/null || echo "0")

echo "🔐 Security Association Arsenal: $sa_count SAs configured"
if [[ "$ipsec_sa" != "No Security Associations" ]] && [[ "$sa_count" -gt 0 ]]; then
    echo -e "${GREEN}📋 Active Security Associations:${NC}"
    echo "$ipsec_sa" | while IFS= read -r line; do
        if [[ "$line" =~ ^\[ ]]; then
            sa_id=$(echo "$line" | grep -o '\[[0-9]*\]')
            echo -e "${PURPLE}  🔒 Security Association $sa_id${NC}"
        elif [[ "$line" =~ "crypto-alg" ]]; then
            crypto_alg=$(echo "$line" | grep -o "crypto-alg [a-zA-Z0-9-]*" | cut -d' ' -f2)
            echo -e "${CYAN}    🛡️  Encryption: $crypto_alg (Guardian's cipher)${NC}"
        elif [[ "$line" =~ "spi" ]]; then
            spi=$(echo "$line" | grep -o "spi [0-9]*" | cut -d' ' -f2)
            echo -e "${BLUE}    🆔 SPI: $spi (Security Parameter Index)${NC}"
        elif [[ "$line" =~ "crypto-key" ]]; then
            echo -e "${YELLOW}    🔑 Encryption Key: [CLASSIFIED] (Guardian's secret)${NC}"
        fi
    done
    
    # Check for our specific encryption
    aes_gcm_count=$(echo "$ipsec_sa" | grep -c "aes-gcm-128" 2>/dev/null || echo "0")
    if [[ "$aes_gcm_count" -gt 0 ]]; then
        echo -e "${GREEN}✅ AES-GCM-128 encryption active - Military-grade protection enabled${NC}"
    else
        echo -e "${YELLOW}⚠️  AES-GCM-128 not found - Check encryption configuration${NC}"
    fi
else
    echo -e "${RED}❌ No Security Associations configured - Guardian is unarmed!${NC}"
fi

echo -e "\n${BLUE}=== Scene 4: Security Policies - The Guardian's Rules ===${NC}"
# IPsec Security Policy Database
spd_info=$(docker exec chain-ipsec vppctl show ipsec spd 2>/dev/null || echo "No Security Policies")
if [[ "$spd_info" != "No Security Policies" ]]; then
    echo -e "${GREEN}📜 Security Policy Database:${NC}"
    echo "$spd_info"
else
    echo -e "${YELLOW}⚠️  No Security Policy Database found${NC}"
fi

# IPsec policies
policies=$(docker exec chain-ipsec vppctl show ipsec policy 2>/dev/null || echo "No policies configured")
if [[ "$policies" != "No policies configured" ]]; then
    echo -e "${GREEN}🛡️  Security Policies:${NC}"
    echo "$policies"
else
    echo -e "${YELLOW}⚠️  No IPsec policies configured${NC}"
fi

echo -e "\n${BLUE}=== Scene 5: Tunnel Status - The Secure Highways ===${NC}"
# IPsec tunnels
ipsec_tunnels=$(docker exec chain-ipsec vppctl show ipsec tunnel 2>/dev/null || echo "No tunnels configured")
tunnel_count=$(echo "$ipsec_tunnels" | grep -c "ipsec" 2>/dev/null || echo "0")

echo "🚇 Secure Tunnel Network: $tunnel_count tunnels"
if [[ "$ipsec_tunnels" != "No tunnels configured" ]] && [[ "$tunnel_count" -gt 0 ]]; then
    echo -e "${GREEN}🚇 Tunnel Configuration:${NC}"
    echo "$ipsec_tunnels"
else
    echo -e "${YELLOW}⚠️  No IPsec tunnels found - Point-to-point encryption mode${NC}"
fi

echo -e "\n${BLUE}=== Scene 6: Encryption Statistics - Guardian's Performance ===${NC}"
# IPsec statistics
ipsec_stats=$(docker exec chain-ipsec vppctl show ipsec statistics 2>/dev/null || echo "No statistics available")
if [[ "$ipsec_stats" != "No statistics available" ]]; then
    echo -e "${GREEN}📊 Encryption Performance:${NC}"
    echo "$ipsec_stats"
else
    echo -e "${YELLOW}⚠️  No IPsec statistics available${NC}"
fi

# Look for encryption/decryption counters
crypto_counters=$(docker exec chain-ipsec vppctl show node counters | grep -i "ipsec\|esp\|ah" 2>/dev/null || echo "No crypto counters")
if [[ "$crypto_counters" != "No crypto counters" ]]; then
    echo -e "\n🔐 Cryptographic Operation Counters:"
    echo -e "${CYAN}$crypto_counters${NC}"
fi

echo -e "\n${BLUE}=== Scene 7: Packet Flow - The Guardian's Recent Actions ===${NC}"
# Recent packet traces for IPsec
echo "🔍 Recent encryption activities:"
docker exec chain-ipsec vppctl clear trace >/dev/null 2>&1 || true

# Enable IPsec-specific tracing
docker exec chain-ipsec vppctl trace add esp-encrypt 20 >/dev/null 2>&1 || true  
docker exec chain-ipsec vppctl trace add esp-decrypt 20 >/dev/null 2>&1 || true
docker exec chain-ipsec vppctl trace add ipsec-output 20 >/dev/null 2>&1 || true
sleep 1

traces=$(docker exec chain-ipsec vppctl show trace 2>/dev/null || echo "No traces available")
if [[ "$traces" != "No traces available" ]]; then
    echo -e "${GREEN}📝 Cryptographic Processing Traces:${NC}"
    echo "$traces" | head -25
    
    # Analyze trace content
    encrypt_count=$(echo "$traces" | grep -ci "encrypt" || echo "0")
    decrypt_count=$(echo "$traces" | grep -ci "decrypt" || echo "0")
    esp_count=$(echo "$traces" | grep -ci "esp" || echo "0")
    
    echo -e "\n📊 Security Operation Analysis:"
    echo -e "${YELLOW}  🔒 Encryption operations: $encrypt_count${NC}"
    echo -e "${YELLOW}  🔓 Decryption operations: $decrypt_count${NC}"
    echo -e "${YELLOW}  📦 ESP packet processing: $esp_count${NC}"
else
    echo -e "${YELLOW}⚠️  No cryptographic traces available${NC}"
    echo "💡 To enable: docker exec chain-ipsec vppctl trace add esp-encrypt 50"
fi

echo -e "\n${BLUE}=== Scene 8: Memory and Cryptographic Performance ===${NC}"
# Memory usage
echo "💾 Guardian's Memory Usage:"
memory_info=$(docker exec chain-ipsec vppctl show memory | head -5 2>/dev/null || echo "Memory info unavailable")
echo -e "${BLUE}$memory_info${NC}"

# Runtime performance for crypto operations
echo -e "\n⚡ Cryptographic Performance:"
runtime=$(docker exec chain-ipsec vppctl show runtime | grep -E "(ipsec|esp|ah|crypto)" | head -10 2>/dev/null || echo "No crypto runtime info")
if [[ "$runtime" != "No crypto runtime info" ]]; then
    echo -e "${BLUE}$runtime${NC}"
fi

echo -e "\n${BLUE}=== Scene 9: Security Alert System ===${NC}"
# Error analysis with security focus
errors=$(docker exec chain-ipsec vppctl show errors | grep -v " 0 " | head -10 2>/dev/null || echo "No errors")
if [[ "$errors" != "No errors" ]]; then
    echo -e "${RED}🚨 Security Alerts and Errors:${NC}"
    echo "$errors"
    
    # Check for security-specific errors
    auth_errors=$(echo "$errors" | grep -i "auth\|verify\|decrypt" || echo "No authentication errors")
    if [[ "$auth_errors" != "No authentication errors" ]]; then
        echo -e "${RED}⚠️  SECURITY BREACH INDICATORS:${NC}"
        echo -e "${RED}$auth_errors${NC}"
    fi
else
    echo -e "${GREEN}✅ No security alerts - Guardian operations are secure${NC}"
fi

echo -e "\n${BLUE}=== Epilogue: IPsec Guardian Health Summary ===${NC}"
# Comprehensive health assessment
if [[ "$container_status" == "running" ]] && [[ "$sa_count" -gt 0 ]]; then
    echo -e "${GREEN}🛡️  SUCCESS: Security Guardian is fully operational${NC}"
    echo -e "${GREEN}🔐 Security Associations: $sa_count active SAs${NC}"
    
    # Check encryption capability
    if [[ "$aes_gcm_count" -gt 0 ]]; then
        echo -e "${GREEN}🔒 Encryption: AES-GCM-128 military-grade protection${NC}"
    fi
    
    # Traffic analysis
    total_rx=$(echo "$interfaces" | grep "rx packets" | head -1 | awk '{print $3}' || echo "0")
    total_tx=$(echo "$interfaces" | grep "tx packets" | head -1 | awk '{print $3}' || echo "0")
    
    if [[ "$total_rx" -gt 0 ]] && [[ "$total_tx" -gt 0 ]]; then
        echo -e "${GREEN}📊 Traffic Protection: Active (RX: $total_rx, TX: $total_tx)${NC}"
    elif [[ "$total_rx" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Traffic: Receiving but not encrypting (check config)${NC}"
    else
        echo -e "${YELLOW}⚠️  Traffic: No packets to protect yet${NC}"
    fi
elif [[ "$container_status" == "running" ]]; then
    echo -e "${YELLOW}⚠️  WARNING: Guardian is active but unarmed (no SAs)${NC}"
else
    echo -e "${RED}❌ CRITICAL: Security Guardian is offline!${NC}"
fi

echo -e "\n📚 End of IPsec Guardian Story - Security Chapter Complete"
echo "========================================================="