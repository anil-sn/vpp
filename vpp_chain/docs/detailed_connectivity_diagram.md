# VPP Multi-Container Chain - Detailed Logical and Physical Connectivity Diagram

## Overview

This document provides a comprehensive view of the VPP Multi-Container Chain's network architecture, including:
- Physical and logical interface mappings
- IP address assignments across all layers
- ARP flow patterns
- Test traffic flow with packet transformations

## Physical and Logical Network Architecture

### Host System Layer
```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                               HOST LINUX SYSTEM                                      │
│                                                                                       │
│  Docker Engine                                                                       │
│  ├── Docker Bridge Networks (managed by docker daemon)                              │
│  │   ├── external-ingress    (172.20.0.0/24, GW: 172.20.0.1)                      │
│  │   ├── ingress-vxlan       (172.20.1.0/24, GW: 172.20.1.1)                      │
│  │   ├── vxlan-nat           (172.20.2.0/24, GW: 172.20.2.1)                      │
│  │   ├── nat-ipsec           (172.20.3.0/24, GW: 172.20.3.1)                      │
│  │   ├── ipsec-fragment      (172.20.4.0/24, GW: 172.20.4.1)                      │
│  │   └── fragment-gcp        (172.20.5.0/24, GW: 172.20.5.1)                      │
│  │                                                                                   │
│  └── Container Network Namespaces                                                    │
│      ├── chain-ingress    (netns)                                                    │
│      ├── chain-vxlan      (netns)                                                    │
│      ├── chain-nat        (netns)                                                    │
│      ├── chain-ipsec      (netns)                                                    │
│      ├── chain-fragment   (netns)                                                    │
│      └── chain-gcp        (netns)                                                    │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Container-Level Interface Architecture

### Container 1: CHAIN-INGRESS (VXLAN Reception)
```
┌─────────────────────────────────────────────────────────────────────────┐
│                       CHAIN-INGRESS CONTAINER                            │
├─────────────────────────────────────────────────────────────────────────┤
│ Container Linux Network Stack                                            │
│ ├── eth0 (container veth)     → 172.20.0.10/24 (external-ingress)      │
│ └── eth1 (container veth)     → 172.20.1.10/24 (ingress-vxlan)         │
│                                                                           │
│ VPP Instance (PID namespace isolated)                                    │
│ ├── host-eth0 (VPP interface) → 172.20.0.10/24                          │
│ │   ├── Maps to container eth0 via AF_PACKET                             │
│ │   └── Receives VXLAN traffic from external sources                     │
│ └── host-eth1 (VPP interface) → 172.20.1.10/24                          │
│     ├── Maps to container eth1 via AF_PACKET                             │
│     └── Forwards packets to VXLAN container                              │
│                                                                           │
│ VPP Forwarding Configuration:                                            │
│ ├── Route: 172.20.1.20/32 via 172.20.1.20 host-eth1                    │
│ └── Route: 172.20.2.0/24 via 172.20.1.20 host-eth1                     │
└─────────────────────────────────────────────────────────────────────────┘
```

### Container 2: CHAIN-VXLAN (VXLAN Decapsulation)
```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CHAIN-VXLAN CONTAINER                             │
├─────────────────────────────────────────────────────────────────────────┤
│ Container Linux Network Stack                                            │
│ ├── eth0 (container veth)     → 172.20.1.20/24 (ingress-vxlan)         │
│ └── eth1 (container veth)     → 172.20.2.10/24 (vxlan-nat)             │
│                                                                           │
│ VPP Instance                                                              │
│ ├── host-eth0 (VPP interface) → 172.20.1.20/24                          │
│ │   └── Receives VXLAN encapsulated packets                              │
│ ├── host-eth1 (VPP interface) → 172.20.2.10/24                          │
│ │   └── Forwards decapsulated inner packets                              │
│ └── vxlan_tunnel0 (VXLAN tunnel interface)                               │
│     ├── Src: 172.20.1.20, Dst: 172.20.1.10, VNI: 100                   │
│     ├── Decapsulates VXLAN headers                                       │
│     └── Extracts inner IP packets                                        │
│                                                                           │
│ VPP Configuration:                                                        │
│ ├── VXLAN Tunnel: src 172.20.1.20 dst 172.20.1.10 vni 100              │
│ └── Route: 10.10.10.0/24 via 172.20.2.20 host-eth1                     │
└─────────────────────────────────────────────────────────────────────────┘
```

### Container 3: CHAIN-NAT (NAT44 Translation)
```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CHAIN-NAT CONTAINER                              │
├─────────────────────────────────────────────────────────────────────────┤
│ Container Linux Network Stack                                            │
│ ├── eth0 (container veth)     → 172.20.2.20/24 (vxlan-nat)             │
│ └── eth1 (container veth)     → 172.20.3.10/24 (nat-ipsec)             │
│                                                                           │
│ VPP Instance with NAT44 Plugin                                           │
│ ├── host-eth0 (VPP interface) → 172.20.2.20/24 [NAT44 INSIDE]           │
│ │   └── Receives inner IP packets from VXLAN                             │
│ ├── host-eth1 (VPP interface) → 172.20.3.10/24 [NAT44 OUTSIDE]          │
│ │   └── Sends NAT-translated packets                                     │
│ └── NAT44 Configuration:                                                  │
│     ├── Address Pool: 172.20.3.10                                        │
│     ├── Static Mapping: 10.10.10.10:2055 → 172.20.3.10:2055 (UDP)      │
│     └── Sessions: 1024 max concurrent                                    │
│                                                                           │
│ Packet Transformation:                                                    │
│ ├── IN:  IP(src=10.10.10.5, dst=10.10.10.10)/UDP(dport=2055)           │
│ └── OUT: IP(src=10.10.10.5, dst=172.20.3.10)/UDP(dport=2055)           │
└─────────────────────────────────────────────────────────────────────────┘
```

### Container 4: CHAIN-IPSEC (IPsec Encryption)
```
┌─────────────────────────────────────────────────────────────────────────┐
│                       CHAIN-IPSEC CONTAINER                              │
├─────────────────────────────────────────────────────────────────────────┤
│ Container Linux Network Stack                                            │
│ ├── eth0 (container veth)     → 172.20.3.20/24 (nat-ipsec)             │
│ └── eth1 (container veth)     → 172.20.4.10/24 (ipsec-fragment)        │
│                                                                           │
│ VPP Instance with IPsec Plugin                                           │
│ ├── host-eth0 (VPP interface) → 172.20.3.20/24                          │
│ │   └── Receives NAT-translated packets                                  │
│ ├── host-eth1 (VPP interface) → 172.20.4.10/24                          │
│ │   └── Sends encrypted packets                                          │
│ ├── ipip0 (IPIP Tunnel Interface) → 10.100.100.1/30                     │
│ │   ├── IPIP Tunnel: src 172.20.3.20 dst 172.20.4.20                    │
│ │   └── Protected by IPsec SAs                                           │
│ └── IPsec Configuration:                                                  │
│     ├── Outbound SA 1000: SPI=1000, ESP, AES-GCM-128                    │
│     ├── Inbound SA 2000:  SPI=2000, ESP, AES-GCM-128                    │
│     └── Crypto Key: 4a506a794f574265564551694d653768                      │
│                                                                           │
│ Packet Transformation:                                                    │
│ ├── IN:  IP(NAT-translated packet)                                       │
│ └── OUT: IP(src=172.20.3.20, dst=172.20.4.20)/ESP(encrypted payload)    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Container 5: CHAIN-FRAGMENT (IP Fragmentation)
```
┌─────────────────────────────────────────────────────────────────────────┐
│                      CHAIN-FRAGMENT CONTAINER                            │
├─────────────────────────────────────────────────────────────────────────┤
│ Container Linux Network Stack                                            │
│ ├── eth0 (container veth)     → 172.20.4.20/24 (ipsec-fragment)        │
│ └── eth1 (container veth)     → 172.20.5.10/24 (fragment-gcp)          │
│                                                                           │
│ VPP Instance                                                              │
│ ├── host-eth0 (VPP interface) → 172.20.4.20/24                          │
│ │   └── Receives IPsec encrypted packets                                 │
│ ├── host-eth1 (VPP interface) → 172.20.5.10/24 [MTU: 1400 bytes]       │
│ │   ├── Output interface with MTU limitation                             │
│ │   └── Triggers IP fragmentation for large packets                      │
│ └── Fragmentation Logic:                                                  │
│     ├── Monitors packet size vs MTU (1400 bytes)                         │
│     ├── Fragments packets > 1400 bytes                                   │
│     ├── Creates fragment headers with proper identification               │
│     └── Maintains fragment sequence and reassembly info                  │
│                                                                           │
│ Packet Transformation (for 8KB test packets):                            │
│ ├── IN:  IP(8000 bytes encrypted packet)                                 │
│ └── OUT: Multiple IP fragments (≤1400 bytes each)                        │
│          ├── Fragment 1: IP(frag_offset=0, MF=1)/data[0:1376]            │
│          ├── Fragment 2: IP(frag_offset=1376, MF=1)/data[1376:2752]      │
│          └── Fragment N: IP(frag_offset=X, MF=0)/data[remaining]          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Container 6: CHAIN-GCP (Final Destination)
```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CHAIN-GCP CONTAINER                               │
├─────────────────────────────────────────────────────────────────────────┤
│ Container Linux Network Stack                                            │
│ └── eth0 (container veth)     → 172.20.5.20/24 (fragment-gcp)          │
│                                                                           │
│ VPP Instance                                                              │
│ ├── host-eth0 (VPP interface) → 172.20.5.20/24                          │
│ │   └── Receives fragmented packets                                      │
│ ├── tap0 (TAP Interface)      → 10.0.3.1/24                             │
│ │   ├── VPP-to-Linux bridge interface                                    │
│ │   └── Enables Linux stack packet processing                           │
│ └── Fragment Reassembly:                                                  │
│     ├── Collects all fragments with same IP ID                          │
│     ├── Reassembles complete packets                                     │
│     └── Forwards to Linux via TAP interface                             │
│                                                                           │
│ Linux Network Stack (inside container)                                   │
│ ├── vpp-tap0 (Linux TAP)      → 10.0.3.2/24                            │
│ │   ├── Connected to VPP tap0 interface                                  │
│ │   └── Receives reassembled packets                                     │
│ └── Packet Capture:                                                       │
│     └── tcpdump -i vpp-tap0 -w /tmp/gcp-received.pcap                   │
└─────────────────────────────────────────────────────────────────────────┘
```

## Complete Network Flow Mapping

### Docker Bridge Network Details
```
HOST LINUX SYSTEM
├── Docker Bridge: br-external-ingress (172.20.0.1/24)
│   └── Connected Containers:
│       └── chain-ingress:eth0 (172.20.0.10/24)
│
├── Docker Bridge: br-ingress-vxlan (172.20.1.1/24)
│   └── Connected Containers:
│       ├── chain-ingress:eth1 (172.20.1.10/24)
│       └── chain-vxlan:eth0 (172.20.1.20/24)
│
├── Docker Bridge: br-vxlan-nat (172.20.2.1/24)
│   └── Connected Containers:
│       ├── chain-vxlan:eth1 (172.20.2.10/24)
│       └── chain-nat:eth0 (172.20.2.20/24)
│
├── Docker Bridge: br-nat-ipsec (172.20.3.1/24)
│   └── Connected Containers:
│       ├── chain-nat:eth1 (172.20.3.10/24)
│       └── chain-ipsec:eth0 (172.20.3.20/24)
│
├── Docker Bridge: br-ipsec-fragment (172.20.4.1/24)
│   └── Connected Containers:
│       ├── chain-ipsec:eth1 (172.20.4.10/24)
│       └── chain-fragment:eth0 (172.20.4.20/24)
│
└── Docker Bridge: br-fragment-gcp (172.20.5.1/24)
    └── Connected Containers:
        ├── chain-fragment:eth1 (172.20.5.10/24)
        └── chain-gcp:eth0 (172.20.5.20/24)
```

## ARP Flow Analysis

### ARP Resolution Patterns
```
1. Container-to-Container ARP within same Docker Bridge:
   ┌─────────────────────────────────────────────────────────────────┐
   │ Example: chain-ingress → chain-vxlan on ingress-vxlan network    │
   ├─────────────────────────────────────────────────────────────────┤
   │                                                                 │
   │ 1. chain-ingress needs to forward to 172.20.1.20               │
   │    ├── VPP host-eth1 sends ARP Request                         │
   │    └── "Who has 172.20.1.20? Tell 172.20.1.10"                │
   │                                                                 │
   │ 2. ARP flows through Docker bridge br-ingress-vxlan            │
   │    ├── Bridge forwards to all connected containers             │
   │    └── L2 broadcast domain within 172.20.1.0/24               │
   │                                                                 │
   │ 3. chain-vxlan VPP host-eth0 responds                          │
   │    ├── ARP Reply: "172.20.1.20 is at MAC:xx:xx:xx:xx:xx:xx"   │
   │    └── Unicast reply back through bridge                       │
   │                                                                 │
   │ 4. ARP table population                                         │
   │    ├── chain-ingress: 172.20.1.20 → MAC address              │
   │    └── chain-vxlan: 172.20.1.10 → MAC address                │
   └─────────────────────────────────────────────────────────────────┘

2. VPP-to-Docker Bridge Gateway ARP:
   ┌─────────────────────────────────────────────────────────────────┐
   │ VPP interfaces learn Docker bridge gateway MAC addresses        │
   ├─────────────────────────────────────────────────────────────────┤
   │                                                                 │
   │ Each VPP interface ARPs for its bridge gateway:                │
   │ ├── host-eth0 → ARP for 172.20.1.1 (br-ingress-vxlan)        │
   │ ├── host-eth1 → ARP for 172.20.2.1 (br-vxlan-nat)           │
   │ └── Results cached in VPP neighbor tables                      │
   └─────────────────────────────────────────────────────────────────┘

3. Cross-Bridge ARP (via routing):
   ┌─────────────────────────────────────────────────────────────────┐
   │ ARP for destinations on different Docker bridges                │
   ├─────────────────────────────────────────────────────────────────┤
   │                                                                 │
   │ Example: chain-nat needs to reach 172.20.4.20                 │
   │ ├── Static routes point to next-hop 172.20.3.20               │
   │ ├── ARP request for next-hop (not final destination)          │
   │ └── Multi-hop ARP resolution through container chain          │
   └─────────────────────────────────────────────────────────────────┘
```

## Test Traffic Flow - Comprehensive Packet Journey

### Traffic Generation Configuration
```
Traffic Generator (Python/Scapy on Host)
├── Target: 172.20.1.20 (chain-vxlan container)
├── VXLAN Configuration:
│   ├── Outer Header: IP(src=host, dst=172.20.1.20)/UDP(dport=4789)
│   ├── VXLAN Header: VXLAN(vni=100)
│   └── Inner Packet: IP(src=10.10.10.5, dst=10.10.10.10)/UDP(dport=2055)
└── Packet Size: 8000 bytes (for fragmentation testing)
```

### End-to-End Traffic Flow with Packet Transformations

#### Stage 1: Traffic Injection → INGRESS Container
```
HOST SYSTEM
├── Scapy generates VXLAN packet
├── Packet structure:
│   ├── Outer: Ethernet()/IP(src=host_ip, dst=172.20.0.10)/UDP(dport=4789)
│   ├── VXLAN: VXLAN(vni=100)
│   └── Inner: IP(src=10.10.10.5, dst=10.10.10.10)/UDP(dport=2055, data=8000_bytes)
└── Injected via host network interface

DOCKER BRIDGE: br-external-ingress
├── L2 forwarding to chain-ingress:eth0
└── MAC address resolution via ARP

CHAIN-INGRESS CONTAINER
├── Container eth0 receives packet (172.20.0.10)
├── VPP host-eth0 processes via AF_PACKET
├── Packet forwarding decision:
│   ├── Destination 172.20.0.10 → local processing
│   └── Route lookup for further forwarding
└── Forward to host-eth1 → 172.20.1.20 (next container)
```

#### Stage 2: INGRESS → VXLAN Container
```
DOCKER BRIDGE: br-ingress-vxlan
├── Receives packet from chain-ingress:eth1 (172.20.1.10)
├── L2 forwarding to chain-vxlan:eth0 (172.20.1.20)
└── ARP resolution for 172.20.1.20

CHAIN-VXLAN CONTAINER
├── VPP host-eth0 receives VXLAN packet
├── VXLAN tunnel processing:
│   ├── Matches VNI 100 on vxlan_tunnel0
│   ├── Strips outer IP/UDP/VXLAN headers
│   └── Extracts inner packet: IP(src=10.10.10.5, dst=10.10.10.10)/UDP(dport=2055)
├── Route lookup: 10.10.10.0/24 via 172.20.2.20
└── Forward decapsulated packet to host-eth1
```

#### Stage 3: VXLAN → NAT Container
```
DOCKER BRIDGE: br-vxlan-nat
├── Receives inner IP packet from chain-vxlan:eth1 (172.20.2.10)
└── Forwards to chain-nat:eth0 (172.20.2.20)

CHAIN-NAT CONTAINER
├── VPP host-eth0 (NAT44 INSIDE) receives packet
├── NAT44 processing:
│   ├── Packet: IP(src=10.10.10.5, dst=10.10.10.10)/UDP(dport=2055)
│   ├── Static mapping lookup: 10.10.10.10:2055 → 172.20.3.10:2055
│   ├── Address translation applied
│   └── Result: IP(src=10.10.10.5, dst=172.20.3.10)/UDP(dport=2055)
├── Session table updated
└── Forward translated packet via host-eth1 (NAT44 OUTSIDE)
```

#### Stage 4: NAT → IPSEC Container
```
DOCKER BRIDGE: br-nat-ipsec
├── Receives NAT-translated packet from chain-nat:eth1 (172.20.3.10)
└── Forwards to chain-ipsec:eth0 (172.20.3.20)

CHAIN-IPSEC CONTAINER
├── VPP host-eth0 receives translated packet
├── IPsec processing:
│   ├── Route lookup indicates tunnel protection required
│   ├── IPIP tunnel encapsulation:
│   │   └── New outer header: IP(src=172.20.3.20, dst=172.20.4.20)
│   ├── ESP encryption with SA 1000:
│   │   ├── Algorithm: AES-GCM-128
│   │   ├── SPI: 1000
│   │   └── Encrypted payload contains original packet
│   └── Result: IP(src=172.20.3.20, dst=172.20.4.20)/ESP(encrypted_data)
└── Forward encrypted packet via host-eth1
```

#### Stage 5: IPSEC → FRAGMENT Container
```
DOCKER BRIDGE: br-ipsec-fragment
├── Receives IPsec packet from chain-ipsec:eth1 (172.20.4.10)
└── Forwards to chain-fragment:eth0 (172.20.4.20)

CHAIN-FRAGMENT CONTAINER
├── VPP host-eth0 receives encrypted packet (8000+ bytes with headers)
├── Fragmentation processing:
│   ├── Output interface MTU check: host-eth1 MTU = 1400 bytes
│   ├── Packet size > MTU → fragmentation required
│   ├── IP fragmentation logic:
│   │   ├── Fragment 1: IP(id=X, offset=0, MF=1)/data[0:1376]
│   │   ├── Fragment 2: IP(id=X, offset=1376, MF=1)/data[1376:2752]
│   │   ├── Fragment 3: IP(id=X, offset=2752, MF=1)/data[2752:4128]
│   │   └── Fragment N: IP(id=X, offset=Y, MF=0)/data[remaining]
│   └── Each fragment ≤ 1400 bytes
└── Forward fragment series via host-eth1
```

#### Stage 6: FRAGMENT → GCP Container (Final Destination)
```
DOCKER BRIDGE: br-fragment-gcp
├── Receives fragment series from chain-fragment:eth1 (172.20.5.10)
└── Forwards to chain-gcp:eth0 (172.20.5.20)

CHAIN-GCP CONTAINER
├── VPP host-eth0 receives fragments
├── Fragment reassembly:
│   ├── Fragment collection by IP identification
│   ├── Reassembly buffer allocation
│   ├── Complete packet reconstruction
│   └── Reassembled: Original 8000+ byte encrypted packet
├── TAP interface forwarding:
│   ├── Route lookup: local processing via tap0
│   └── Forward to tap0 (VPP → Linux bridge)
└── Linux stack processing:
    ├── vpp-tap0 receives packet (10.0.3.2/24)
    ├── Packet capture: tcpdump writes to /tmp/gcp-received.pcap
    └── Final packet validation and logging
```

## Interface Mapping Summary Table

| Container | Linux eth | IP Address | VPP Interface | Docker Bridge | Role |
|-----------|-----------|------------|---------------|---------------|------|
| **chain-ingress** | eth0 | 172.20.0.10/24 | host-eth0 | br-external-ingress | VXLAN reception |
|                   | eth1 | 172.20.1.10/24 | host-eth1 | br-ingress-vxlan | Forward to VXLAN |
| **chain-vxlan** | eth0 | 172.20.1.20/24 | host-eth0 | br-ingress-vxlan | Receive from INGRESS |
|                 | eth1 | 172.20.2.10/24 | host-eth1 | br-vxlan-nat | Forward to NAT |
|                 | - | - | vxlan_tunnel0 | - | VXLAN decapsulation |
| **chain-nat** | eth0 | 172.20.2.20/24 | host-eth0 | br-vxlan-nat | NAT INSIDE |
|               | eth1 | 172.20.3.10/24 | host-eth1 | br-nat-ipsec | NAT OUTSIDE |
| **chain-ipsec** | eth0 | 172.20.3.20/24 | host-eth0 | br-nat-ipsec | Receive from NAT |
|                 | eth1 | 172.20.4.10/24 | host-eth1 | br-ipsec-fragment | Forward to FRAGMENT |
|                 | - | 10.100.100.1/30 | ipip0 | - | IPsec tunnel |
| **chain-fragment** | eth0 | 172.20.4.20/24 | host-eth0 | br-ipsec-fragment | Receive from IPsec |
|                    | eth1 | 172.20.5.10/24 | host-eth1 | br-fragment-gcp | Forward to GCP |
| **chain-gcp** | eth0 | 172.20.5.20/24 | host-eth0 | br-fragment-gcp | Final destination |
|               | - | 10.0.3.1/24 | tap0 | - | VPP-Linux bridge |
|               | vpp-tap0 | 10.0.3.2/24 | - | - | Linux TAP interface |

## Performance and Monitoring Points

### Key Observation Points for Traffic Flow
```
1. Packet Injection Point:
   ├── Host network interface → br-external-ingress
   └── Monitor: tcpdump on host interface

2. VXLAN Processing:
   ├── chain-vxlan VPP: vppctl show vxlan tunnel
   └── Monitor: vppctl trace add af-packet-input 50

3. NAT Translation:
   ├── chain-nat VPP: vppctl show nat44 sessions
   └── Monitor: vppctl show nat44 static mappings

4. IPsec Encryption:
   ├── chain-ipsec VPP: vppctl show ipsec sa
   └── Monitor: vppctl show ipsec tunnel

5. Fragmentation:
   ├── chain-fragment VPP: vppctl show interface
   └── Monitor: Interface statistics for fragment counts

6. Final Reception:
   ├── chain-gcp: /tmp/gcp-received.pcap
   └── Monitor: tcpdump output and packet reassembly
```

This comprehensive diagram shows the complete path from traffic generation through all container transformations to final destination, including all interface mappings, IP addresses, ARP flows, and packet transformation details at each stage of the VPP processing pipeline.