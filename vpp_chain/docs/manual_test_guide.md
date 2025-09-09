# VPP Multi-Container Chain Manual Test Guide

This comprehensive guide provides step-by-step manual testing commands for validating the VPP multi-container packet processing chain. Each command includes expected results and troubleshooting guidance.

## Overview

The VPP chain processes packets through 6 specialized containers:
```
[Traffic Generator] → INGRESS → VXLAN → NAT44 → IPsec → FRAGMENT → GCP
                     172.20.0.10  172.20.1.20  172.20.2.20  172.20.3.20  172.20.4.20  172.20.5.20
```

## Phase 1: Infrastructure Validation

### 1.1 Container Status Check
```bash
# Command: Check all containers are running
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "Checking $container..."
  docker ps | grep $container || echo "❌ $container not running"
done

# Expected: All containers should show as running
# Why: Basic prerequisite - all containers must be operational before testing
```

### 1.2 VPP Process Health Check
```bash
# Command: Verify VPP processes are responsive in each container
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "Testing VPP in $container..."
  docker exec $container vppctl show version | head -3
  echo "Status: $(docker exec $container vppctl show version >/dev/null 2>&1 && echo '✅ VPP OK' || echo '❌ VPP FAILED')"
done

# Expected: Each container should respond with VPP version information
# Why: VPP must be running and responsive for packet processing
```

### 1.3 Network Interface Status
```bash
# Command: Check VPP interface configuration
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "=== $container Interface Status ==="
  docker exec $container vppctl show interface
  docker exec $container vppctl show interface address
  echo
done

# Expected: All interfaces should be 'up' with non-zero RX/TX counters
# Why: Interfaces must be operational for packet flow
```

## Phase 2: Layer 3 Connectivity Testing

### 2.1 Within-Network Connectivity (VPP L3 Routing)
```bash
# Command: Test L3 routing within each network segment
echo "=== Testing within-network L3 connectivity ==="

# Ingress network (172.20.0.x)
echo "Chain-ingress → Gateway (172.20.0.1):"
docker exec chain-ingress ping -c 2 -W 1 172.20.0.1
# Expected: 2 packets transmitted, 2 received, 0% packet loss
# Why: Validates basic L3 connectivity to Docker network gateway

# VXLAN network (172.20.1.x)  
echo "Chain-vxlan → Chain-ingress (172.20.1.10):"
docker exec chain-vxlan ping -c 2 -W 1 172.20.1.10
# Expected: 2 packets transmitted, 2 received, 0% packet loss
# Why: Tests VXLAN container can reach ingress gateway
```

### 2.2 Cross-Container L3 Routing
```bash
# Command: Test L3 routing between container pairs
containers=("chain-ingress:172.20.1.20" "chain-vxlan:172.20.2.20" "chain-nat:172.20.3.20" "chain-ipsec:172.20.4.20" "chain-fragment:172.20.5.20")
src_containers=("chain-ingress" "chain-vxlan" "chain-nat" "chain-ipsec" "chain-fragment")

for i in {0..4}; do
  IFS=':' read -r dst_container dst_ip <<< "${containers[$i]}"
  src_container="${src_containers[$i]}"
  echo "L3 Test: $src_container → $dst_ip"
  docker exec $src_container ping -c 1 -W 2 $dst_ip >/dev/null 2>&1
  echo "Result: $([ $? -eq 0 ] && echo '✅ SUCCESS' || echo '❌ FAILED (Expected for VPP-only containers)')"
done

# Expected: Most will FAIL because VPP drops ICMP ping packets by design
# Why: VPP is optimized for packet processing, not network diagnostics
# Note: Failure is EXPECTED and does not indicate routing problems
```

## Phase 3: UDP Traffic Flow Testing (Recommended Method)

### 3.1 Individual Hop UDP Testing
```bash
# Command: Test UDP connectivity between each container pair
echo "=== UDP Connectivity Test (Reliable method for VPP) ==="

# Hop 1: chain-ingress → chain-vxlan
timeout 2 docker exec chain-vxlan nc -l -u -p 2000 &
sleep 1 && echo "test1" | timeout 2 docker exec -i chain-ingress nc -u -w 1 172.20.1.20 2000
echo "Hop 1 Result: $([ $? -eq 0 ] && echo '✅ SUCCESS' || echo '❌ FAILED')"

# Hop 2: chain-vxlan → chain-nat  
timeout 2 docker exec chain-nat nc -l -u -p 2001 &
sleep 1 && echo "test2" | timeout 2 docker exec -i chain-vxlan nc -u -w 1 172.20.2.20 2001
echo "Hop 2 Result: $([ $? -eq 0 ] && echo '✅ SUCCESS' || echo '❌ FAILED')"

# Hop 3: chain-nat → chain-ipsec
timeout 2 docker exec chain-ipsec nc -l -u -p 2002 &
sleep 1 && echo "test3" | timeout 2 docker exec -i chain-nat nc -u -w 1 172.20.3.20 2002
echo "Hop 3 Result: $([ $? -eq 0 ] && echo '✅ SUCCESS' || echo '❌ FAILED')"

# Hop 4: chain-ipsec → chain-fragment
timeout 2 docker exec chain-fragment nc -l -u -p 2003 &
sleep 1 && echo "test4" | timeout 2 docker exec -i chain-ipsec nc -u -w 1 172.20.4.20 2003
echo "Hop 4 Result: $([ $? -eq 0 ] && echo '✅ SUCCESS' || echo '❌ FAILED')"

# Hop 5: chain-fragment → chain-gcp
timeout 2 docker exec chain-gcp nc -l -u -p 2004 &
sleep 1 && echo "test5" | timeout 2 docker exec -i chain-fragment nc -u -w 1 172.20.5.20 2004
echo "Hop 5 Result: $([ $? -eq 0 ] && echo '✅ SUCCESS' || echo '❌ FAILED')"

# Expected: All hops should show SUCCESS
# Why: UDP traffic tests actual packet forwarding capabilities
```

### 3.2 End-to-End UDP Flow
```bash
# Command: Test complete chain UDP connectivity
echo "=== End-to-End UDP Test ==="
timeout 3 docker exec chain-gcp nc -l -u -p 2055 &
sleep 1
echo "end-to-end-test" | timeout 3 docker exec -i chain-ingress nc -u -w 1 172.20.5.20 2055
echo "End-to-End Result: $([ $? -eq 0 ] && echo '✅ SUCCESS' || echo '❌ FAILED')"

# Expected: SUCCESS indicates full L3 routing chain works
# Why: Validates complete packet path through all containers
```

## Phase 4: VPP Routing Table Analysis

### 4.1 FIB (Forwarding Information Base) Inspection
```bash
# Command: Examine routing tables in each container
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "=== $container Routing Table ==="
  docker exec $container vppctl show ip fib | grep -E "(172.20|default)"
  echo
done

# Expected: Each container should have routes to next hop networks
# Why: Proper routing is essential for packet forwarding
```

### 4.2 ARP Table Verification
```bash
# Command: Check ARP neighbor resolution
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "=== $container ARP Neighbors ==="
  docker exec $container vppctl show ip neighbors
  echo
done

# Expected: Active ARP entries for adjacent container IPs
# Why: L2/L3 resolution must work for packet forwarding
```

## Phase 5: Specialized Function Validation

### 5.1 VXLAN Configuration Check
```bash
# Command: Verify VXLAN tunnel configuration
echo "=== VXLAN Tunnel Status ==="
docker exec chain-vxlan vppctl show vxlan tunnel
docker exec chain-vxlan vppctl show bridge-domain

# Expected: VXLAN tunnel with VNI 100, src 172.20.1.20, dst 172.20.1.10
# Why: VXLAN decapsulation requires proper tunnel configuration
```

### 5.2 NAT44 Configuration Check
```bash
# Command: Verify NAT44 translation rules
echo "=== NAT44 Configuration ==="
docker exec chain-nat vppctl show nat44 static mappings
docker exec chain-nat vppctl show nat44 addresses
docker exec chain-nat vppctl show nat44 interfaces

# Expected: Static mapping 10.10.10.10 → 172.20.3.10:2055
# Why: NAT translation must be configured for address mapping
```

### 5.3 IPsec Configuration Check
```bash
# Command: Verify IPsec SA and policies
echo "=== IPsec Configuration ==="
docker exec chain-ipsec vppctl show ipsec sa
docker exec chain-ipsec vppctl show ipsec tunnel

# Expected: SA entries with AES-GCM-128 encryption configured
# Why: IPsec encryption requires security associations
```

### 5.4 Fragmentation Interface Check
```bash
# Command: Check fragmentation capabilities
echo "=== Fragmentation Configuration ==="
docker exec chain-fragment vppctl show interface | grep -A5 -B5 mtu

# Expected: Interfaces with MTU settings that enable fragmentation
# Why: Large packets (>1400 bytes) must be fragmented
```

## Phase 6: Packet Tracing and Traffic Analysis

### 6.1 Enable Packet Tracing
```bash
# Command: Enable packet tracing on all containers
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "Enabling trace on $container..."
  docker exec $container vppctl clear trace
  docker exec $container vppctl trace add af-packet-input 50
done

# Expected: Tracing enabled confirmation for each container
# Why: Packet traces show actual packet processing flow
```

### 6.2 Generate Test Traffic and Analyze
```bash
# Command: Run traffic test with tracing
echo "=== Running Traffic Test with Tracing ==="
timeout 10 sudo python3 src/main.py test --type traffic &
TRAFFIC_PID=$!
sleep 8

# Collect traces from each container
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "=== $container Packet Trace ==="
  docker exec $container vppctl show trace | head -20
  echo
done

wait $TRAFFIC_PID

# Expected: Packet traces showing VXLAN, IP, UDP processing
# Why: Traces reveal exact packet processing behavior and errors
```

### 6.3 Traffic Statistics Analysis
```bash
# Command: Check interface statistics after traffic test
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "=== $container Interface Statistics ==="
  docker exec $container vppctl show interface | grep -E "(rx packets|tx packets|drops)"
  echo
done

# Expected: RX/TX counters increment, drops should be minimal
# Why: High drop counts indicate packet processing issues
```

## Phase 7: VXLAN Traffic Generation Test

### 7.1 Manual VXLAN Packet Creation
```bash
# Command: Create and send VXLAN packet using Python/Scapy
python3 -c "
from scapy.all import *
import time

# Create inner payload (UDP packet to be processed)
inner_pkt = IP(src='10.10.10.5', dst='10.10.10.10')/UDP(sport=1234, dport=2055)/('A'*100)

# VXLAN encapsulation
vxlan_pkt = IP(src='172.20.0.1', dst='172.20.0.10')/UDP(sport=12345, dport=4789)/VXLAN(vni=100, flags=0x08)/inner_pkt

# Send packet and capture response
print('Sending VXLAN packet...')
send(vxlan_pkt, iface='br-d91b47a0512b')  # Use correct bridge interface
print('VXLAN packet sent successfully')
"

# Expected: Packet sent without errors
# Why: Tests manual VXLAN packet injection into the chain
```

### 7.2 Verify VXLAN Processing
```bash
# Command: Check if VXLAN packet was processed
echo "=== VXLAN Processing Verification ==="

# Check ingress for VXLAN reception
docker exec chain-ingress vppctl show trace | grep -i vxlan || echo "No VXLAN traces in ingress"

# Check vxlan container for decapsulation
docker exec chain-vxlan vppctl show trace | grep -E "(vxlan|decap)" || echo "No VXLAN decapsulation traces"

# Check NAT for address translation
docker exec chain-nat vppctl show nat44 sessions | grep -E "(10.10.10|172.20.3)" || echo "No active NAT sessions"

# Expected: Evidence of VXLAN processing in traces and statistics
# Why: Confirms end-to-end VXLAN packet processing functionality
```

## Phase 8: Troubleshooting Commands

### 8.1 Common Issues Diagnosis
```bash
# Command: Diagnose high drop counts
echo "=== Drop Analysis ==="
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "$container drops:"
  docker exec $container vppctl show interface | awk '/drops/ {print $2}' | head -6
done

# Expected: Low drop counts (<10% of total packets)
# Why: High drops indicate configuration or MAC address issues

# Command: Check interface MAC addresses
echo "=== MAC Address Verification ==="
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "$container MAC addresses:"
  docker exec $container ip link show | grep -E "eth[0-9]" -A1
done

# Expected: Valid MAC addresses on all interfaces
# Why: L2 forwarding requires correct MAC addressing
```

### 8.2 VPP Error Analysis
```bash
# Command: Check VPP error counters
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "=== $container VPP Errors ==="
  docker exec $container vppctl show errors | head -10
done

# Expected: Minimal error counts
# Why: VPP errors indicate specific processing issues
```

## Summary and Interpretation

### Success Criteria:
1. **All containers running**: Docker ps shows 6 containers active
2. **VPP responsive**: All vppctl commands succeed
3. **UDP connectivity**: All 5 hops successful + end-to-end test passes
4. **Specialized functions configured**: VXLAN tunnels, NAT mappings, IPsec SAs present
5. **Packet processing**: Traces show packets moving through chain with minimal drops

### Expected Failures (Normal Behavior):
1. **ICMP ping failures**: VPP drops ping packets by design - use UDP instead
2. **L2 MAC "errors"**: VPP operates in L3 mode, not L2 bridging
3. **Some interface drops**: Normal during initial ARP resolution

### Critical Issues to Investigate:
1. **High drop counts** (>50%): Usually MAC address or L2/L3 configuration issues
2. **No UDP connectivity**: Routing table or interface configuration problems  
3. **Missing specialized configs**: VXLAN tunnels, NAT mappings, IPsec SAs not configured
4. **No packet traces**: Traffic not reaching containers or VPP not processing

This guide provides comprehensive manual testing capabilities for the entire VPP multi-container chain, with clear expectations and troubleshooting guidance for each phase.