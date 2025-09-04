# VPP Multi-Container Chain Architecture

## Overview

This document provides detailed architectural information about the VPP multi-container chain implementation.

## System Components

### 1. Container Chain Architecture

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   INGRESS   │───▶│   VXLAN     │───▶│    NAT44    │───▶│   IPSEC     │───▶│ FRAGMENT    │───▶ [GCP]
│ 192.168.10.2│    │ Decap VNI   │    │ 10.10.10.10 │    │ AES-GCM-128 │    │  MTU 1400   │
│   Receives  │    │    100      │    │ → 10.1.3.1  │    │ Encryption  │    │ IP Fragments│
│VXLAN Traffic│    │ UDP:4789    │    │  Port:2055  │    │ ESP Tunnel  │    │ Large Pkts  │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

### 2. Network Topology

#### Underlay Network (192.168.10.0/24)
- **Purpose**: Main network for external traffic ingress and egress
- **Gateway**: 192.168.10.1
- **Containers**: 
  - chain-ingress: 192.168.10.2
  - chain-fragment: 192.168.10.4
  - chain-gcp: 192.168.10.3

#### Inter-Container Networks
- **chain-1-2** (10.1.1.0/24): Ingress ↔ VXLAN
- **chain-2-3** (10.1.2.0/24): VXLAN ↔ NAT
- **chain-3-4** (10.1.3.0/24): NAT ↔ IPsec
- **chain-4-5** (10.1.4.0/24): IPsec ↔ Fragment

### 3. Container Specifications

#### INGRESS Container (chain-ingress)
- **Function**: VXLAN packet reception and initial processing
- **Networks**: underlay, chain-1-2
- **IP Addresses**: 192.168.10.2, 10.1.1.1
- **VPP Configuration**: Host interfaces with packet forwarding

#### VXLAN Container (chain-vxlan) 
- **Function**: VXLAN decapsulation (VNI 100)
- **Networks**: chain-1-2, chain-2-3
- **IP Addresses**: 10.1.1.2, 10.1.2.1
- **VPP Configuration**: VXLAN tunnel + bridge domain

#### NAT Container (chain-nat)
- **Function**: NAT44 translation
- **Networks**: chain-2-3, chain-3-4
- **IP Addresses**: 10.1.2.2, 10.1.3.1
- **VPP Configuration**: NAT44 with static mapping (10.10.10.10:2055 → 10.1.3.1:2055)

#### IPsec Container (chain-ipsec)
- **Function**: ESP encryption with AES-GCM-128
- **Networks**: chain-3-4, chain-4-5  
- **IP Addresses**: 10.1.3.2, 10.1.4.1
- **VPP Configuration**: IPIP tunnel with IPsec protection

#### Fragment Container (chain-fragment)
- **Function**: IP fragmentation for large packets
- **Networks**: chain-4-5, underlay
- **IP Addresses**: 10.1.4.2, 192.168.10.4
- **VPP Configuration**: MTU 1400 with fragmentation enabled

#### GCP Container (chain-gcp)
- **Function**: Destination endpoint with packet capture
- **Networks**: underlay
- **IP Addresses**: 192.168.10.3
- **VPP Configuration**: TAP interface + IP reassembly

## Data Flow

### 1. Packet Processing Pipeline

```
[External Traffic] 
       ↓
[INGRESS: VXLAN Reception]
       ↓ 
[VXLAN: Decapsulation VNI 100]
       ↓
[NAT: Address Translation] 
       ↓
[IPSEC: ESP Encryption]
       ↓
[FRAGMENT: MTU Processing]
       ↓
[GCP: Final Destination]
```

### 2. Example Traffic Flow

1. **Input**: VXLAN packet (src: 192.168.10.100, dst: 192.168.10.2, VNI: 100)
   - Inner: IP(src: 10.10.10.10, dst: 10.0.3.1) / UDP(sport: 12345, dport: 2055)

2. **INGRESS**: Receives VXLAN packet on underlay network

3. **VXLAN**: Decapsulates VNI 100, extracts inner packet

4. **NAT**: Translates 10.10.10.10:2055 → 10.1.3.1:2055

5. **IPsec**: Encrypts with ESP AES-GCM-128 in IPIP tunnel

6. **FRAGMENT**: Fragments if packet > 1400 bytes

7. **GCP**: Reassembles fragments and delivers to TAP interface

## VPP Configuration Details

### Startup Configuration
- **no-pci**: Prevents VPP from claiming host interfaces
- **Essential plugins**: af_packet, vxlan, nat, ipsec, crypto_native
- **Memory**: 256M main heap, 16384 buffers per NUMA
- **Debug logging**: Enabled for all VPP components

### Interface Management
- **Host interfaces**: Used for inter-container communication
- **Bridge domains**: For L2 VXLAN processing
- **IP routing**: Configured per container for traffic forwarding
- **Features**: Enabled per interface (forwarding, NAT, IPsec, fragmentation)

## Performance Considerations

### VPP Optimizations
- **Buffer management**: Optimized for 2048-byte packets
- **Memory allocation**: Dedicated per-NUMA buffers
- **Plugin selection**: Only essential plugins loaded
- **No multi-seg**: Simplified packet handling

### Container Resources
- **Privileged mode**: Required for VPP networking operations
- **Memory limits**: Unlimited memlock for VPP
- **Capabilities**: NET_ADMIN, SYS_ADMIN, IPC_LOCK
- **Volume mounts**: Read-only configs, writable logs

## Monitoring and Debugging

### Built-in Monitoring
- **Packet tracing**: Enabled on all containers
- **Interface statistics**: Available via vppctl
- **Log aggregation**: Centralized in /tmp/vpp-logs
- **Packet capture**: Available in GCP container

### Debug Commands
```bash
# Container status
python3 src/main.py status

# VPP CLI access
docker exec -it <container> vppctl

# Debug specific container
sudo python3 src/main.py debug <container> "<command>"

# Monitor chain
python3 src/main.py monitor --duration 60
```