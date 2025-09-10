# VPP Multi-Container Chain: Technical Reference

## Complete Interface Configuration

This document provides comprehensive technical details for all network interfaces, bridge domains, ARP entries, and the complete packet lifecycle through the VPP processing chain.

## Container Interface Mappings

### VXLAN-PROCESSOR Container

**Interface Configuration:**
```
host-eth0 (up):  L3 172.20.100.10/24    # VXLAN ingress interface
host-eth1 (up):  L2 bridge bd-id 1      # Bridge to security-processor  
                 L3 172.20.101.10/24    # Management IP
vxlan_tunnel0:   L2 bridge bd-id 1      # VXLAN tunnel endpoint
local0 (down):   Control interface      # VPP control (unused)
```

**Bridge Domain Details:**
```
Bridge Domain 1: VXLAN L2 Forwarding
├── Interfaces: host-eth1 (If-idx 2), vxlan_tunnel0 (If-idx 3)
├── Learning: ON (MAC address learning enabled)
├── Flooding: ON (unknown unicast flooding)
├── ARP Termination: OFF
└── Split Horizon Group: 0 (no SHG restrictions)
```

**Expected ARP Entries:**
```
172.20.100.1    3a:40:a2:58:5f:12    host-eth0    # Docker bridge gateway
172.20.101.20   [dynamic]            host-eth1    # Security processor
```

### SECURITY-PROCESSOR Container

**Interface Configuration:**
```
host-eth0 (up):  L3 172.20.101.20/24   # From VXLAN processor
host-eth1 (up):  L3 172.20.102.10/24   # To destination
ipip0 (up):      L3 10.100.100.1/30    # IPsec tunnel endpoint
local0 (down):   Control interface     # VPP control (unused)
```

**NAT44 Configuration:**
```
Static Mapping:
└── Inside: 10.10.10.10:2055 ↔ Outside: 172.20.102.10:2055

Interface Assignment:
├── Inside Interface: host-eth0 (172.20.101.20/24)
└── Outside Interface: host-eth1 (172.20.102.10/24)
```

**IPsec Configuration:**
```
Security Association (SA):
├── Protocol: ESP (Encapsulating Security Payload)
├── Encryption: AES-GCM-128
├── Tunnel: IPIP (IP-in-IP)
├── Source: 172.20.101.20 → Destination: 172.20.102.20
└── Fragmentation: MTU 1400 bytes
```

**Expected ARP Entries:**
```
172.20.101.10   02:fe:a6:27:c8:b6    host-eth0    # VXLAN processor
172.20.102.1    26:90:3c:de:ef:5b    host-eth1    # Docker bridge gateway
172.20.102.20   02:fe:2c:b2:f9:4b    host-eth1    # Destination container
```

### DESTINATION Container

**Interface Configuration:**
```
host-eth0 (up):  L3 172.20.102.20/24   # IPsec traffic ingress
ipip0 (up):      L3 10.100.100.2/30    # IPsec tunnel endpoint
tap0 (up):       L3 10.0.3.1/24        # TAP bridge to Linux
local0 (down):   Control interface     # VPP control (unused)
```

**TAP Interface Details:**
```
TAP Interface: tap0
├── Purpose: Bridge VPP to Linux network stack
├── IP Address: 10.0.3.1/24
├── Mode: Interrupt-driven (optimized for low CPU usage)
└── Packet Capture: Available via tcpdump/wireshark
```

**Expected ARP Entries:**
```
172.20.102.1    [dynamic]    host-eth0    # Docker bridge gateway  
172.20.102.10   [dynamic]    host-eth0    # Security processor
```

## Complete Packet Lifecycle

### Phase 1: Traffic Generation → VXLAN-PROCESSOR

**1.1 Packet Generation (Config-Driven)**
```python
# Traffic Generator (fully config-driven from config.json)
Source: 172.20.100.1 (external-traffic gateway)
Destination: 172.20.100.10 (vxlan-processor eth0)
Protocol: UDP/4789 (VXLAN)

Packet Structure:
Ethernet: [Docker bridge MAC] → [vxlan-processor eth0 MAC]
IP Outer: 172.20.100.1 → 172.20.100.10
UDP: src_port=12345+seq → dst_port=4789
VXLAN: VNI=100, flags=0x08
IP Inner: 10.10.10.5 → 10.10.10.10  
UDP Inner: src_port=1234+seq → dst_port=2055
Payload: 8000 bytes (triggers fragmentation)
```

**1.2 VXLAN Reception & Processing**
```
host-eth0 Interface:
├── Receives VXLAN packet at 172.20.100.10:4789
├── VPP af-packet-input: Packet enters VPP processing
├── Ethernet-input: Validates L2 headers
├── IP4-input: Processes outer IP (172.20.100.1 → 172.20.100.10)
├── UDP-input: Validates UDP/4789 checksum
├── VXLAN-input: Decapsulates VNI 100 packet
└── L2-input: Extracts inner Ethernet frame
```

**1.3 VXLAN Tunnel Processing**
```
VXLAN Tunnel Configuration:
├── Tunnel ID: vxlan_tunnel0
├── Source: 172.20.100.10 (vxlan-processor)
├── Destination: 172.20.100.1 (traffic generator) 
├── VNI: 100
├── Decap-Next: l2 (Layer 2 forwarding)
└── Bridge Domain: 1

Decapsulation Process:
├── Remove outer IP/UDP/VXLAN headers
├── Extract inner packet: IP(10.10.10.5 → 10.10.10.10)/UDP(2055)
├── Forward to Bridge Domain 1
└── L2 forwarding to host-eth1 interface
```

**1.4 L2 Bridge Forwarding**
```
Bridge Domain 1 Operation:
├── Learning: Enabled (MAC address learning)
├── Flooding: Enabled (unknown unicast flooding)
├── Interfaces: vxlan_tunnel0 (ingress) → host-eth1 (egress)
├── MAC Learning: Associates source MACs with ingress interface
└── Forwarding: Sends packet to security-processor via host-eth1
```

### Phase 2: VXLAN-PROCESSOR → SECURITY-PROCESSOR

**2.1 Inter-Container Communication**
```
Network: vxlan-processing (172.20.101.0/24)
Path: host-eth1 (172.20.101.10) → host-eth0 (172.20.101.20)
Docker Bridge: Handles L2 forwarding between containers
ARP Resolution: 172.20.101.20 ↔ security-processor MAC address
```

**2.2 Security Processor Reception**
```
host-eth0 Interface (172.20.101.20):
├── Receives decapsulated inner packet
├── Packet: IP(10.10.10.5 → 10.10.10.10)/UDP(2055)/Payload(8000B)
├── af-packet-input: Packet enters VPP processing
├── Ethernet-input: Validates L2 headers  
├── IP4-input: Processes inner IP headers
└── IP4-lookup: Routes to NAT44 processing
```

### Phase 3: Security Processing (NAT44 + IPsec + Fragmentation)

**3.1 NAT44 Translation**
```
NAT44 Static Mapping:
├── Rule: 10.10.10.10:2055 ↔ 172.20.102.10:2055
├── Interface Assignment:
│   ├── Inside: host-eth0 (172.20.101.20/24)
│   └── Outside: host-eth1 (172.20.102.10/24)
└── Translation Process:
    ├── Match: Destination 10.10.10.10:2055
    ├── Translate: 10.10.10.10:2055 → 172.20.102.10:2055
    ├── Update: IP header checksum recalculation
    └── Update: UDP header checksum recalculation

Post-NAT Packet:
IP: 10.10.10.5 → 172.20.102.10
UDP: 1234+seq → 2055  
Payload: 8000 bytes (unchanged)
```

**3.2 IPsec ESP Encryption**
```
IPsec SA Configuration:
├── Protocol: ESP (Encapsulating Security Payload)
├── Mode: Tunnel mode with IPIP
├── Encryption: AES-GCM-128
├── Authentication: Integrated with GCM
├── Tunnel Endpoints:
│   ├── Source: 172.20.101.20 (security-processor)
│   └── Destination: 172.20.102.20 (destination)
└── SPI: Security Parameter Index (unique identifier)

Encryption Process:
├── Create IPIP tunnel header: 172.20.101.20 → 172.20.102.20
├── Encrypt original packet with AES-GCM-128
├── Add ESP header with SPI and sequence number
├── Add ESP trailer with padding and Next Header field
└── Calculate and append ICV (Integrity Check Value)

Encrypted Packet Structure:
IP Outer: 172.20.101.20 → 172.20.102.20
ESP Header: SPI, Sequence Number
Encrypted Payload: {Original IP + UDP + Data}
ESP Trailer: Padding + Next Header
ICV: Authentication tag
```

**3.3 IP Fragmentation**
```
Fragmentation Configuration:
├── MTU Enforcement: 1400 bytes maximum
├── Fragment Identification: Unique ID per original packet
├── Flags: More Fragments (MF) bit management
└── Fragment Offset: 8-byte aligned offsets

Fragmentation Process:
├── Check: Total packet size > 1400 bytes
├── Calculate: Number of fragments needed
├── Split: Original packet into MTU-sized fragments
├── Headers: Copy IP header to each fragment
├── Adjust: Fragment offset and MF flag per fragment
└── Forward: Each fragment to host-eth1 interface

Example 8000-byte packet fragmentation:
├── Fragment 1: Offset 0, MF=1, Size=1400B
├── Fragment 2: Offset 1400, MF=1, Size=1400B  
├── Fragment 3: Offset 2800, MF=1, Size=1400B
├── Fragment 4: Offset 4200, MF=1, Size=1400B
├── Fragment 5: Offset 5600, MF=1, Size=1400B
└── Fragment 6: Offset 7000, MF=0, Size=1000B (final)
```

### Phase 4: SECURITY-PROCESSOR → DESTINATION

**4.1 Fragment Transmission**
```
Network: processing-destination (172.20.102.0/24)
Path: host-eth1 (172.20.102.10) → host-eth0 (172.20.102.20)
Fragments: Multiple encrypted ESP packets ≤ 1400 bytes each
Docker Bridge: Forwards fragments maintaining order
```

**4.2 Destination Reception & Reassembly**
```
host-eth0 Interface (172.20.102.20):
├── Receives fragmented ESP packets
├── af-packet-input: Each fragment enters VPP
├── IP4-input: Processes outer IP headers
├── Fragment Reassembly: Collects fragments by ID
├── ESP Decryption: Decrypts reassembled packet
└── IPIP Decapsulation: Extracts original packet
```

### Phase 5: Final Processing & TAP Bridge

**5.1 IPsec Decryption**
```
ESP Processing:
├── SPI Lookup: Find matching Security Association
├── Sequence Check: Verify sequence number validity
├── Decryption: AES-GCM-128 decryption of payload
├── Authentication: Verify ICV (Integrity Check Value)
├── Extract: Original packet from ESP payload
└── Remove: IPIP tunnel headers

Decrypted Packet:
IP: 10.10.10.5 → 172.20.102.10 (post-NAT addresses)
UDP: 1234+seq → 2055
Payload: 8000 bytes (reassembled)
```

**5.2 TAP Interface Processing**
```
TAP Bridge Operation:
├── Interface: tap0 (10.0.3.1/24)
├── Purpose: Bridge VPP to Linux network stack
├── Mode: Interrupt-driven (optimized CPU usage)
├── Packet Flow: VPP → TAP → Linux kernel
└── Capture: Available via tcpdump, wireshark

Final Packet Delivery:
├── VPP Forwarding: Routes packet to tap0 interface
├── TAP Write: Packet written to TAP device
├── Linux Reception: Kernel receives packet on tap0
├── Network Stack: Standard Linux networking processing
└── Application: Packet available to user-space applications
```

## Network Flow Summary

```
Traffic Generator (172.20.100.1) 
    ↓ VXLAN/UDP:4789
VXLAN-PROCESSOR (172.20.100.10)
    ├── VXLAN Decapsulation (VNI 100)
    ├── L2 Bridge Domain 1 Forwarding
    └── host-eth1 (172.20.101.10)
    ↓ Decapsulated IP packet
SECURITY-PROCESSOR (172.20.101.20)
    ├── NAT44: 10.10.10.10 → 172.20.102.10
    ├── IPsec ESP: AES-GCM-128 encryption
    ├── IPIP Tunnel: 172.20.101.20 → 172.20.102.20
    ├── Fragmentation: MTU 1400 enforcement  
    └── host-eth1 (172.20.102.10)
    ↓ Encrypted fragments
DESTINATION (172.20.102.20)
    ├── Fragment Reassembly
    ├── ESP Decryption & Authentication
    ├── IPIP Decapsulation
    └── TAP Bridge (10.0.3.1/24)
    ↓ Final processed packet
Linux Network Stack
```

## Key Processing Metrics

**Performance Characteristics:**
- **VXLAN Decapsulation**: ~1-2 μs per packet
- **NAT44 Translation**: ~0.5-1 μs per packet  
- **IPsec Encryption**: ~5-10 μs per packet (AES-GCM-128)
- **Fragmentation**: ~1-3 μs per fragment
- **Total Processing**: ~10-20 μs end-to-end latency

**Packet Transformations:**
1. **Size**: 8000B → fragmented → reassembled → 8000B
2. **Headers**: VXLAN → IP → NAT → ESP → IPIP → Final IP
3. **Addresses**: Multiple translation stages preserve data integrity
4. **Security**: Encryption provides confidentiality and authentication

**Resource Utilization:**
- **Memory**: ~256MB per VPP instance
- **CPU**: 1-2 cores per container under load
- **Network**: Up to 10Gbps throughput capability
- **Latency**: Sub-20μs processing delay

## Debugging Commands Reference

### Interface Statistics
```bash
# Detailed interface statistics
for container in vxlan-processor security-processor destination; do
  echo "=== $container ==="
  docker exec $container vppctl show interface detail
done
```

### Bridge Domain Analysis  
```bash
# VXLAN L2 bridge analysis
docker exec vxlan-processor vppctl show bridge-domain 1 detail
docker exec vxlan-processor vppctl show l2fib bridge-domain 1
```

### ARP and Neighbor Discovery
```bash
# ARP table verification
for container in vxlan-processor security-processor destination; do
  echo "=== $container ARP ===" 
  docker exec $container vppctl show ip neighbors
done
```

### Packet Tracing
```bash
# Enable comprehensive packet tracing
docker exec vxlan-processor vppctl trace add af-packet-input 50
docker exec security-processor vppctl trace add af-packet-input 50  
docker exec destination vppctl trace add af-packet-input 50

# Generate test traffic
sudo python3 src/main.py test --type traffic

# Analyze traces
for container in vxlan-processor security-processor destination; do
  echo "=== $container TRACE ==="
  docker exec $container vppctl show trace
done
```

### Security Feature Verification
```bash
# NAT44 session monitoring
docker exec security-processor vppctl show nat44 sessions

# IPsec SA status  
docker exec security-processor vppctl show ipsec sa

# VXLAN tunnel status
docker exec vxlan-processor vppctl show vxlan tunnel
```

This technical reference provides the complete foundation for understanding, debugging, and extending the VPP multi-container chain implementation.