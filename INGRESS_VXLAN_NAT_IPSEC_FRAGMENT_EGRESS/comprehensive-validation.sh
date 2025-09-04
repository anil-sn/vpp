#!/bin/bash
# Comprehensive VPP Chain Validation Script
# This script tells the complete story of our VPP chain like reading a novel

set -e

# Colors for better storytelling
RED='\033[0;31m'
GREEN='\033[0;32m' 
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Logging function with timestamps and storytelling
log_story() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    
    case $level in
        "CHAPTER")
            echo -e "\n${WHITE}===============================================${NC}"
            echo -e "${WHITE}📚 CHAPTER: $message${NC}"
            echo -e "${WHITE}===============================================${NC}\n"
            ;;
        "SCENE")
            echo -e "\n${CYAN}🎬 SCENE: $message${NC}"
            echo -e "${CYAN}-------------------------------------------${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}✅ [$timestamp] SUCCESS: $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ [$timestamp] ERROR: $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  [$timestamp] WARNING: $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  [$timestamp] INFO: $message${NC}"
            ;;
        "TRACE")
            echo -e "${PURPLE}🔍 [$timestamp] TRACE: $message${NC}"
            ;;
    esac
}

# Function to capture VPP packet traces at entry/exit points
capture_vpp_traces() {
    local container=$1
    local description=$2
    
    log_story "TRACE" "Capturing packet traces for $container - $description"
    
    # Clear previous traces
    docker exec $container vppctl clear trace >/dev/null 2>&1 || true
    
    # Enable tracing
    docker exec $container vppctl trace add af-packet-input 50 >/dev/null 2>&1 || true
    docker exec $container vppctl trace add host-eth0-output 50 >/dev/null 2>&1 || true
    docker exec $container vppctl trace add host-eth1-output 50 >/dev/null 2>&1 || true
    
    # Wait for some traffic
    sleep 2
    
    # Capture and display traces
    local traces=$(docker exec $container vppctl show trace 2>/dev/null || echo "No traces available")
    if [[ "$traces" != "No traces available" ]]; then
        log_story "TRACE" "Packet flow in $container:\n$traces"
    else
        log_story "WARNING" "No packet traces captured for $container"
    fi
}

# Function to validate Docker Compose setup
validate_docker_compose() {
    log_story "CHAPTER" "Docker Compose Validation - The Infrastructure Story"
    
    log_story "SCENE" "Validating Docker Compose Configuration"
    
    # Check if docker-compose.yml exists
    if [[ ! -f "docker-compose.yml" ]]; then
        log_story "ERROR" "docker-compose.yml not found - Our story cannot begin without the script!"
        exit 1
    fi
    log_story "SUCCESS" "Found docker-compose.yml - The script is ready"
    
    # Validate compose file syntax
    if docker compose config >/dev/null 2>&1; then
        log_story "SUCCESS" "Docker Compose configuration is syntactically correct"
    else
        log_story "ERROR" "Docker Compose configuration has syntax errors"
        docker compose config
        exit 1
    fi
    
    # Check network definitions
    log_story "INFO" "Analyzing network topology..."
    local networks=$(docker compose config | grep -A 5 "networks:" | grep "^ *[a-z]" | grep -v "networks:" | awk '{print $1}' | tr -d ':')
    for network in $networks; do
        log_story "SUCCESS" "Network '$network' defined in our topology"
    done
    
    # Check service dependencies
    log_story "INFO" "Validating service dependencies - The chain of events..."
    local services=$(docker compose config --services)
    for service in $services; do
        local depends_on=$(docker compose config | grep -A 10 "^  $service:" | grep "depends_on:" -A 5 | grep "^ *-" | awk '{print $2}' || echo "")
        if [[ -n "$depends_on" ]]; then
            log_story "INFO" "Service '$service' depends on: $depends_on"
        else
            log_story "INFO" "Service '$service' has no dependencies - An independent character"
        fi
    done
}

# Function to validate individual containers
validate_containers() {
    log_story "CHAPTER" "Container Validation - Meeting Our Characters"
    
    local expected_containers=("chain-ingress" "chain-vxlan" "chain-nat" "chain-ipsec" "chain-fragment" "chain-gcp")
    
    for container in "${expected_containers[@]}"; do
        log_story "SCENE" "Validating Container: $container"
        
        # Check if container exists
        if docker ps -a --format "table {{.Names}}" | grep -q "^$container$"; then
            log_story "SUCCESS" "Container '$container' exists in our cast"
        else
            log_story "ERROR" "Container '$container' is missing from our story!"
            continue
        fi
        
        # Check if container is running
        if docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            log_story "SUCCESS" "Container '$container' is alive and running"
        else
            log_story "ERROR" "Container '$container' exists but is not running - A character in trouble!"
            docker logs $container --tail 20
            continue
        fi
        
        # Check container health
        local uptime=$(docker inspect $container --format "{{.State.StartedAt}}" | xargs -I {} date -d {} +%s)
        local now=$(date +%s)
        local duration=$((now - uptime))
        log_story "INFO" "Container '$container' has been running for ${duration} seconds"
        
        # Check resource usage
        local stats=$(docker stats $container --no-stream --format "CPU: {{.CPUPerc}}, Memory: {{.MemUsage}}")
        log_story "INFO" "Container '$container' resource usage: $stats"
        
        # Check if VPP is responsive in container
        if docker exec $container vppctl show version >/dev/null 2>&1; then
            local vpp_version=$(docker exec $container vppctl show version 2>/dev/null | head -1)
            log_story "SUCCESS" "VPP in '$container' is responsive: $vpp_version"
        else
            log_story "ERROR" "VPP in '$container' is not responsive - Our character is unconscious!"
        fi
    done
}

# Function to validate VPP configurations
validate_vpp_configs() {
    log_story "CHAPTER" "VPP Configuration Validation - Character Development"
    
    local containers=("chain-ingress" "chain-vxlan" "chain-nat" "chain-ipsec" "chain-fragment" "chain-gcp")
    
    for container in "${containers[@]}"; do
        log_story "SCENE" "VPP Configuration Analysis for $container"
        
        # Interface validation
        log_story "INFO" "Examining interfaces in $container..."
        local interfaces=$(docker exec $container vppctl show interface 2>/dev/null || echo "No interfaces")
        if [[ "$interfaces" != "No interfaces" ]]; then
            echo "$interfaces" | while read -r line; do
                if [[ "$line" =~ ^[[:space:]]*[a-zA-Z] ]]; then
                    log_story "SUCCESS" "Interface found in $container: $(echo $line | awk '{print $1, $2, $3}')"
                fi
            done
        else
            log_story "WARNING" "No interfaces configured in $container"
        fi
        
        # Memory and buffer validation
        local memory=$(docker exec $container vppctl show memory 2>/dev/null | head -5 || echo "Memory info unavailable")
        log_story "INFO" "Memory status in $container:\n$memory"
        
        # Plugin validation
        local plugins=$(docker exec $container vppctl show plugins 2>/dev/null | grep "Loaded:" || echo "Plugin info unavailable")
        if [[ "$plugins" != "Plugin info unavailable" ]]; then
            log_story "SUCCESS" "Plugins loaded in $container:\n$plugins"
        fi
        
        # Container-specific validations
        case $container in
            "chain-vxlan")
                log_story "INFO" "Checking VXLAN-specific configuration..."
                local vxlan_tunnels=$(docker exec $container vppctl show vxlan tunnel 2>/dev/null || echo "No VXLAN tunnels")
                if [[ "$vxlan_tunnels" != "No VXLAN tunnels" ]]; then
                    log_story "SUCCESS" "VXLAN tunnels in $container:\n$vxlan_tunnels"
                else
                    log_story "WARNING" "No VXLAN tunnels found in $container"
                fi
                ;;
            "chain-nat")
                log_story "INFO" "Checking NAT-specific configuration..."
                local nat_config=$(docker exec $container vppctl show nat44 addresses 2>/dev/null || echo "No NAT config")
                if [[ "$nat_config" != "No NAT config" ]]; then
                    log_story "SUCCESS" "NAT configuration in $container:\n$nat_config"
                else
                    log_story "WARNING" "No NAT configuration found in $container"
                fi
                ;;
            "chain-ipsec")
                log_story "INFO" "Checking IPsec-specific configuration..."
                local ipsec_sa=$(docker exec $container vppctl show ipsec sa 2>/dev/null || echo "No IPsec SA")
                if [[ "$ipsec_sa" != "No IPsec SA" ]]; then
                    log_story "SUCCESS" "IPsec Security Associations in $container:\n$ipsec_sa"
                else
                    log_story "WARNING" "No IPsec Security Associations found in $container"
                fi
                ;;
        esac
    done
}

# Function to validate connectivity
validate_connectivity() {
    log_story "CHAPTER" "Connectivity Validation - The Network Relationships"
    
    log_story "SCENE" "Inter-Container Network Connectivity"
    
    # Test ping between adjacent containers
    local connectivity_tests=(
        "chain-ingress:10.1.1.1:chain-vxlan:10.1.1.2"
        "chain-vxlan:10.1.2.1:chain-nat:10.1.2.2" 
        "chain-nat:10.1.3.1:chain-ipsec:10.1.3.2"
        "chain-ipsec:10.1.4.1:chain-fragment:10.1.4.2"
        "chain-fragment:192.168.10.20:chain-gcp:192.168.10.30"
    )
    
    for test in "${connectivity_tests[@]}"; do
        local from_container=$(echo $test | cut -d: -f1)
        local from_ip=$(echo $test | cut -d: -f2)
        local to_container=$(echo $test | cut -d: -f3)
        local to_ip=$(echo $test | cut -d: -f4)
        
        log_story "INFO" "Testing connectivity: $from_container ($from_ip) → $to_container ($to_ip)"
        
        # Using docker network connectivity
        if docker exec $from_container ping -c 2 -W 2 $to_ip >/dev/null 2>&1; then
            log_story "SUCCESS" "✅ Connection established: $from_container can reach $to_container"
        else
            log_story "WARNING" "⚠️  Connection issue: $from_container cannot reach $to_container directly"
            # Try alternative connectivity test via docker network
            if docker exec $from_container ping -c 1 -W 1 $to_container >/dev/null 2>&1; then
                log_story "SUCCESS" "✅ Docker network connectivity: $from_container ↔ $to_container"
            else
                log_story "ERROR" "❌ No connectivity between $from_container and $to_container"
            fi
        fi
    done
}

# Function to validate tunnels
validate_tunnels() {
    log_story "CHAPTER" "Tunnel Validation - The Secret Passages"
    
    log_story "SCENE" "VXLAN Tunnel Validation"
    
    # Check VXLAN tunnel in vxlan container
    local vxlan_status=$(docker exec chain-vxlan vppctl show vxlan tunnel 2>/dev/null || echo "No tunnels")
    if [[ "$vxlan_status" != "No tunnels" ]]; then
        log_story "SUCCESS" "VXLAN tunnel operational:\n$vxlan_status"
        
        # Check VXLAN tunnel statistics
        local vxlan_stats=$(docker exec chain-vxlan vppctl show interface vxlan_tunnel0 2>/dev/null || echo "No stats")
        if [[ "$vxlan_stats" != "No stats" ]]; then
            log_story "INFO" "VXLAN tunnel statistics:\n$vxlan_stats"
        fi
    else
        log_story "ERROR" "VXLAN tunnel not found or not configured"
    fi
    
    log_story "SCENE" "IPsec Tunnel Validation"
    
    # Check IPsec Security Associations
    local ipsec_sa=$(docker exec chain-ipsec vppctl show ipsec sa 2>/dev/null || echo "No SA")
    if [[ "$ipsec_sa" != "No SA" ]]; then
        log_story "SUCCESS" "IPsec Security Associations active:\n$ipsec_sa"
        
        # Check IPsec tunnel statistics
        local ipsec_stats=$(docker exec chain-ipsec vppctl show ipsec tunnel 2>/dev/null || echo "No tunnel stats")
        if [[ "$ipsec_stats" != "No tunnel stats" ]]; then
            log_story "INFO" "IPsec tunnel statistics:\n$ipsec_stats"
        fi
    else
        log_story "ERROR" "IPsec Security Associations not found"
    fi
}

# Function to perform end-to-end traffic validation with tracing
validate_traffic_with_tracing() {
    log_story "CHAPTER" "Traffic Validation with Full Tracing - The Grand Performance"
    
    log_story "SCENE" "Preparing the Stage - Enabling Packet Traces"
    
    # Enable packet tracing on all containers
    local containers=("chain-ingress" "chain-vxlan" "chain-nat" "chain-ipsec" "chain-fragment" "chain-gcp")
    for container in "${containers[@]}"; do
        log_story "INFO" "Enabling packet tracing in $container"
        docker exec $container vppctl clear trace >/dev/null 2>&1 || true
        docker exec $container vppctl trace add af-packet-input 100 >/dev/null 2>&1 || true
        docker exec $container vppctl trace add host-eth0-output 100 >/dev/null 2>&1 || true
        docker exec $container vppctl trace add host-eth1-output 100 >/dev/null 2>&1 || true
        docker exec $container vppctl trace add vxlan-input 100 >/dev/null 2>&1 || true
        docker exec $container vppctl trace add nat44-ed-in2out 100 >/dev/null 2>&1 || true
        docker exec $container vppctl trace add ipsec-encrypt 100 >/dev/null 2>&1 || true
    done
    
    log_story "SCENE" "Act I - Generating Test Traffic"
    
    # Generate test traffic using Python
    log_story "INFO" "Sending VXLAN-encapsulated UDP traffic to the chain..."
    
    # Start packet capture on GCP endpoint  
    log_story "INFO" "Starting packet capture on destination..."
    docker exec -d chain-gcp tcpdump -i vpp-tap0 -w /tmp/gcp-received.pcap -c 10 2>/dev/null || true
    
    # Generate traffic using Python/Scapy
    cat > /tmp/traffic_generator.py << 'EOF'
#!/usr/bin/env python3
import sys
import time
from scapy.all import *

def generate_vxlan_traffic():
    print("Generating VXLAN traffic...")
    
    # Create inner payload
    inner_payload = IP(src="10.10.10.10", dst="10.0.3.1") / UDP(sport=2055, dport=2055) / Raw("Hello from VXLAN tunnel!")
    
    # Create VXLAN header
    vxlan_pkt = Ether() / IP(src="192.168.10.1", dst="192.168.10.10") / UDP(sport=12345, dport=4789) / VXLAN(vni=100) / inner_payload
    
    # Send packets
    for i in range(5):
        send(vxlan_pkt, verbose=0)
        print(f"Sent packet {i+1}")
        time.sleep(0.5)
    
    print("Traffic generation completed")

if __name__ == "__main__":
    generate_vxlan_traffic()
EOF
    
    python3 /tmp/traffic_generator.py 2>/dev/null || log_story "WARNING" "Traffic generation failed - continuing with traces"
    
    # Wait for traffic processing
    sleep 5
    
    log_story "SCENE" "Act II - Analyzing Packet Traces at Each Stage"
    
    # Capture traces from each container showing the packet journey
    for container in "${containers[@]}"; do
        case $container in
            "chain-ingress")
                log_story "SCENE" "📥 INGRESS CONTAINER - Where the journey begins"
                capture_vpp_traces $container "VXLAN packet reception"
                ;;
            "chain-vxlan") 
                log_story "SCENE" "📦 VXLAN CONTAINER - Unwrapping the package"
                capture_vpp_traces $container "VXLAN decapsulation"
                ;;
            "chain-nat")
                log_story "SCENE" "🔄 NAT CONTAINER - Address transformation"
                capture_vpp_traces $container "NAT44 translation"
                local nat_sessions=$(docker exec $container vppctl show nat44 sessions 2>/dev/null || echo "No sessions")
                log_story "INFO" "NAT sessions:\n$nat_sessions"
                ;;
            "chain-ipsec")
                log_story "SCENE" "🔒 IPSEC CONTAINER - Securing the payload"
                capture_vpp_traces $container "IPsec encryption"
                ;;
            "chain-fragment")
                log_story "SCENE" "✂️  FRAGMENT CONTAINER - Breaking down for delivery"
                capture_vpp_traces $container "IP fragmentation"
                ;;
            "chain-gcp")
                log_story "SCENE" "🎯 GCP CONTAINER - Final destination"
                capture_vpp_traces $container "Packet reassembly and delivery"
                ;;
        esac
        
        # Show interface statistics for this container
        local interface_stats=$(docker exec $container vppctl show interface 2>/dev/null | grep -E "(host-eth|vxlan|tap)" || echo "No relevant interfaces")
        if [[ "$interface_stats" != "No relevant interfaces" ]]; then
            log_story "INFO" "Interface statistics for $container:\n$interface_stats"
        fi
    done
    
    log_story "SCENE" "Act III - Final Results and Packet Capture Analysis"
    
    # Wait for packet capture to complete
    sleep 2
    
    # Analyze captured packets at destination
    local captured_packets=$(docker exec chain-gcp tcpdump -r /tmp/gcp-received.pcap -c 10 2>/dev/null | wc -l || echo "0")
    if [[ "$captured_packets" -gt 0 ]]; then
        log_story "SUCCESS" "🎉 End-to-end success! Captured $captured_packets packets at destination"
        local packet_details=$(docker exec chain-gcp tcpdump -r /tmp/gcp-received.pcap -nn 2>/dev/null || echo "No details")
        log_story "INFO" "Captured packet details:\n$packet_details"
    else
        log_story "WARNING" "No packets captured at destination - investigating..."
        
        # Check if packets are stuck somewhere in the chain
        for container in "${containers[@]}"; do
            local rx_packets=$(docker exec $container vppctl show interface 2>/dev/null | grep -A 1 "host-eth" | grep "rx packets" | head -1 | awk '{print $3}' || echo "0")
            if [[ "$rx_packets" -gt 0 ]]; then
                log_story "INFO" "$container received $rx_packets packets"
            fi
        done
    fi
    
    # Clean up
    rm -f /tmp/traffic_generator.py
}

# Main validation orchestration
main() {
    local timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    local log_file="validation_log_${timestamp}.txt"
    
    log_story "CHAPTER" "VPP Chain Comprehensive Validation - The Complete Story"
    log_story "INFO" "Starting comprehensive validation at $(date)"
    log_story "INFO" "Logging to: $log_file"
    
    # Run all validation phases
    validate_docker_compose
    validate_containers  
    validate_vpp_configs
    validate_connectivity
    validate_tunnels
    validate_traffic_with_tracing
    
    log_story "CHAPTER" "Epilogue - The Story Concludes"
    log_story "SUCCESS" "Comprehensive validation completed at $(date)"
    log_story "INFO" "Full story logged to: $log_file"
    
    echo -e "\n${WHITE}📖 THE END${NC}"
    echo -e "${WHITE}Our VPP chain story has been told in full detail.${NC}"
    echo -e "${WHITE}Check the logs above to understand the complete journey${NC}"
    echo -e "${WHITE}of packets through our network processing pipeline.${NC}\n"
}

# Execute with logging
main 2>&1 | tee "validation_log_$(date '+%Y-%m-%d_%H-%M-%S').txt"