# VPP Multi-Container Chain Architecture

## Overview

This document provides comprehensive architectural specifications for the VPP multi-container chain implementation. The system implements a high-performance network processing pipeline using Vector Packet Processing (VPP) v24.10-release across six specialized Docker containers, processing packets through VXLAN decapsulation, NAT44 translation, IPsec encryption, and IP fragmentation.

## System Architecture

### Container Processing Pipeline

The VPP multi-container chain implements a six-stage packet processing pipeline:

```
INGRESS → VXLAN → NAT44 → IPSEC → FRAGMENT → GCP
```

Each container runs a dedicated VPP instance configured for specific network functions, connected through Docker bridge networks using the 172.20.x.x addressing scheme.

### Network Topology

#### External Ingress Network (172.20.0.0/24)
- **Purpose**: External network for VXLAN traffic ingress
- **Gateway**: 172.20.0.1
- **INGRESS Container**: 172.20.0.10

#### Inter-Container Networks
- **ingress-vxlan** (172.20.1.0/24): Ingress to VXLAN communication
- **vxlan-nat** (172.20.2.0/24): VXLAN to NAT communication
- **nat-ipsec** (172.20.3.0/24): NAT to IPsec communication
- **ipsec-fragment** (172.20.4.0/24): IPsec to Fragment communication
- **fragment-gcp** (172.20.5.0/24): Fragment to GCP communication

## Container Specifications

### INGRESS Container (chain-ingress)
- **Primary Function**: VXLAN packet reception and forwarding
- **Networks**: external-ingress (172.20.0.10), ingress-vxlan (172.20.1.10)
- **VPP Configuration**: 
  - Host interfaces created with `create host-interface name eth0/eth1`
  - Packet forwarding between networks
  - Traffic ingress point for VXLAN encapsulated packets
- **Dockerfile**: `src/containers/ingress/Dockerfile.ingress`
- **Configuration Script**: `ingress-config.sh`

### VXLAN Container (chain-vxlan)
- **Primary Function**: VXLAN decapsulation (VNI 100)
- **Networks**: ingress-vxlan (172.20.1.20), vxlan-nat (172.20.2.10)
- **VPP Configuration**:
  - VXLAN tunnel endpoint on UDP port 4789
  - Bridge domain configuration for L2/L3 processing
  - VNI 100 decapsulation with inner packet extraction
- **Dockerfile**: `src/containers/vxlan/Dockerfile.vxlan`
- **Configuration Script**: `vxlan-config.sh`

### NAT Container (chain-nat)
- **Primary Function**: NAT44 address translation
- **Networks**: vxlan-nat (172.20.2.20), nat-ipsec (172.20.3.10)
- **VPP Configuration**:
  - NAT44 plugin with static mapping
  - Address translation: 10.10.10.10 → 172.20.3.10
  - Port translation for UDP port 2055
- **Dockerfile**: `src/containers/Dockerfile.base`
- **Configuration Script**: `nat-config.sh`

### IPsec Container (chain-ipsec)
- **Primary Function**: IPsec ESP encryption with AES-GCM-128
- **Networks**: nat-ipsec (172.20.3.20), ipsec-fragment (172.20.4.10)
- **VPP Configuration**:
  - IPsec ESP tunnel with AES-GCM-128 encryption
  - IPIP tunnel for packet encapsulation
  - Crypto engine for hardware acceleration support
- **Dockerfile**: `src/containers/ipsec/Dockerfile.ipsec`
- **Configuration Script**: `ipsec-config.sh`

### Fragment Container (chain-fragment)
- **Primary Function**: IP fragmentation for large packets
- **Networks**: ipsec-fragment (172.20.4.20), fragment-gcp (172.20.5.10)
- **VPP Configuration**:
  - MTU set to 1400 bytes on output interface
  - IP fragmentation for packets exceeding MTU
  - Handles jumbo packets up to 8KB tested
- **Dockerfile**: `src/containers/fragment/Dockerfile.fragment`
- **Configuration Script**: `fragment-config.sh`

### GCP Container (chain-gcp)
- **Primary Function**: Final destination endpoint
- **Networks**: fragment-gcp (172.20.5.20)
- **VPP Configuration**:
  - Packet reception and reassembly
  - Final traffic validation endpoint
- **Dockerfile**: `src/containers/Dockerfile.base`
- **Configuration Script**: `gcp-config.sh`

## Packet Processing Flow

### Processing Pipeline

The VPP multi-container chain processes packets through six distinct stages:

```
External VXLAN Traffic
        ↓
[INGRESS: 172.20.0.10]
        ↓ (172.20.1.x network)
[VXLAN: Decapsulation VNI 100]
        ↓ (172.20.2.x network)
[NAT44: Address Translation]
        ↓ (172.20.3.x network)
[IPSEC: ESP AES-GCM-128 Encryption]
        ↓ (172.20.4.x network)
[FRAGMENT: MTU 1400 Processing]
        ↓ (172.20.5.x network)
[GCP: Final Destination]
```

### Traffic Flow Example

1. **External Input**: VXLAN packet received at INGRESS container
   - Outer: IP(src: external, dst: 172.20.0.10) / UDP(dport: 4789) / VXLAN(vni: 100)
   - Inner: IP(src: 10.10.10.5, dst: 10.10.10.10) / UDP(sport: random, dport: 2055)

2. **INGRESS Processing**: Packet forwarding to VXLAN container
   - Receives VXLAN encapsulated traffic
   - Forwards to 172.20.1.20 (VXLAN container)

3. **VXLAN Decapsulation**: VNI 100 processing
   - Extracts inner IP packet from VXLAN encapsulation
   - Forwards decapsulated packet to NAT container

4. **NAT44 Translation**: Address and port mapping
   - Translates source address: 10.10.10.10 → 172.20.3.10
   - Maintains port mapping for UDP port 2055
   - Forwards translated packet to IPsec container

5. **IPsec Encryption**: ESP tunnel establishment
   - Encrypts packet with AES-GCM-128 algorithm
   - Encapsulates in IPIP tunnel for transport
   - Forwards encrypted packet to Fragment container

6. **IP Fragmentation**: MTU boundary handling
   - Fragments packets exceeding 1400 byte MTU limit
   - Supports jumbo packet processing up to 8KB
   - Forwards fragments to GCP destination

7. **GCP Destination**: Final packet processing
   - Reassembles fragmented packets
   - Final traffic validation and capture

## VPP Configuration Architecture

### VPP Startup Configuration

Each container implements standardized VPP startup configuration:

```
unix {
  no-pci
  log /tmp/vpp.log
  full-coredump
  cli-listen /run/vpp/cli.sock
  runtime-dir /run/vpp
  gid vpp
}

api-trace { on }
api-segment { gid vpp }
socksvr { default }

memory {
  main-heap-size 256M
  main-heap-page-size 2M
}

buffers {
  buffers-per-numa 16384
  default data-size 2048
}

plugins {
  plugin default { disable }
  plugin af_packet_plugin.so { enable }
  plugin vxlan_plugin.so { enable }
  plugin nat_plugin.so { enable }
  plugin ipsec_plugin.so { enable }
  plugin crypto_native_plugin.so { enable }
}
```

### Interface Configuration Standards

**Host Interface Creation**:
- Syntax: `create host-interface name ethX`
- IP Assignment: `set interface ip address host-ethX <ip>/<prefix>`
- State Management: `set interface state host-ethX up`

**Bridge Domain Configuration** (VXLAN container):
- Bridge creation with VXLAN tunnel integration
- L2/L3 mode switching for packet processing
- MAC learning and flooding control

**Routing Configuration**:
- Static routes configured per container for traffic forwarding
- Default gateway assignment for external connectivity
- Inter-container route establishment

## Performance and Resource Management

### VPP Performance Optimization

**Buffer Management**:
- Default packet data size: 2048 bytes
- Buffer allocation: 16384 buffers per NUMA node
- Main heap allocation: 256MB with 2MB page size
- No multi-segment buffer support for simplified processing

**Memory Architecture**:
- Main heap: 256MB allocated with huge pages
- Per-NUMA buffer distribution for NUMA-aware processing
- Shared memory segments for API communication
- Runtime directory: /run/vpp for socket communication

**Plugin Architecture**:
- Selective plugin loading (default disabled)
- Essential plugins: af_packet, vxlan, nat, ipsec, crypto_native
- Minimal plugin footprint for reduced memory consumption

### Container Resource Requirements

**Docker Container Configuration**:
- Privileged mode: Required for VPP network interface management
- Capabilities: NET_ADMIN, SYS_ADMIN, IPC_LOCK
- Memory limits: Unlimited memlock for VPP shared memory
- Volume mounts: Configuration (read-only), logs (writable)

**Network Interface Access**:
- Host network namespace access for interface creation
- Kernel bypass capabilities for high-performance packet processing
- Memory-mapped I/O for direct hardware access

### Jumbo Packet Processing

**Large Packet Support**:
- Maximum tested packet size: 8KB (8000 bytes)
- Fragmentation boundary: 1400 bytes MTU
- Fragment reassembly at destination container
- Buffer chain handling for oversized packets

## System Monitoring and Diagnostics

### Built-in Monitoring Capabilities

**VPP Telemetry**:
- Packet tracing: `vppctl trace add <interface> <count>`
- Interface statistics: `vppctl show interface`
- Hardware counters: `vppctl show hardware-interfaces`
- Memory usage: `vppctl show memory`

**Log Management**:
- VPP logs: /tmp/vpp.log in each container
- API trace logs: Enabled for debugging
- System logs: Docker container logs
- Debug verbosity: Configurable per VPP component

**Packet Capture**:
- VPP packet capture: `vppctl pcap trace rx tx`
- Interface-specific captures for traffic analysis
- Packet inspection at each processing stage

### Diagnostic Commands

**System Status**:
```bash
# Overall chain status
python3 src/main.py status

# Container health verification
sudo python3 src/main.py test --type connectivity

# Traffic flow validation
sudo python3 src/main.py test --type traffic
```

**Container-Level Debugging**:
```bash
# VPP CLI access
docker exec -it <container-name> vppctl

# Execute VPP commands
sudo python3 src/main.py debug <container> "show interface addr"
sudo python3 src/main.py debug <container> "show ip fib"
sudo python3 src/main.py debug <container> "show nat44 sessions"
```

**Performance Monitoring**:
```bash
# Real-time monitoring
python3 src/main.py monitor --duration 120

# Comprehensive validation
sudo ./comprehensive-validation.sh
```

## Technical Implementation Details

### VPP Version and Compatibility
- VPP Version: v24.10-release
- API compatibility: Stable API usage across containers
- Plugin compatibility: Tested with essential plugin set
- Hardware support: x86_64 architecture optimized

### Network Function Implementation

**VXLAN Processing**:
- VNI: 100 (configurable)
- UDP Port: 4789 (standard VXLAN port)
- Multicast support: Disabled for point-to-point operation
- MAC learning: Enabled for bridge domain operation

**NAT44 Implementation**:
- Translation type: Static mapping
- Address pool: Single address mapping
- Session tracking: UDP session management
- Port allocation: Deterministic port mapping

**IPsec Configuration**:
- Algorithm: AES-GCM-128 for authenticated encryption
- Mode: Tunnel mode with IPIP encapsulation
- Key management: Pre-shared keys (demonstration)
- Protocol: ESP (Encapsulating Security Payload)

**Fragmentation Handling**:
- MTU enforcement: 1400 bytes on output interface
- Fragment identification: Standard IP fragmentation
- Reassembly: Performed at destination container
- Maximum fragment size: Aligned with network MTU requirements