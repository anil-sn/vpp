# VPP Multi-Container Chain: Consolidated Network Processing Pipeline

[![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)](https://python.org)
[![Docker](https://img.shields.io/badge/Docker-20.10+-blue.svg)](https://docker.com)
[![VPP](https://img.shields.io/badge/VPP-24.10+-green.svg)](https://fd.io)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

This project showcases a high-performance, consolidated network processing pipeline using Vector Packet Processing (VPP) v24.10-release distributed across three specialized Docker containers. The optimized architecture implements VXLAN decapsulation, Network Address Translation (NAT44), IPsec encryption, and packet fragmentation with 50% reduced resource footprint while maintaining full functionality.

### Architecture and Processing Flow

The optimized architecture consists of three specialized Docker containers that provide comprehensive network processing. Data flows through this efficient chain in the following sequence:

1.  **VXLAN-PROCESSOR (vxlan-processor):** Receives incoming VXLAN-encapsulated UDP traffic on 172.20.0.10:4789 and decapsulates VXLAN packets targeting VNI 100 to extract inner IP packets
2.  **SECURITY-PROCESSOR (security-processor):** Consolidated processing container that performs:
    - NAT44 translation mapping inner packet addresses (10.10.10.10:2055 → 172.20.2.10:2055)
    - IPsec ESP encryption with AES-GCM-128 in an IPIP tunnel
    - IP fragmentation for packets exceeding MTU of 1400 bytes
3.  **DESTINATION (destination):** Final destination endpoint that receives processed and reassembled packets via TAP interface with packet capture capabilities

### Container and Network Setup

The project uses Python-based container management to orchestrate the three containers. Each container is connected via dedicated Docker networks in a streamlined topology:

*   **external-traffic (172.20.0.0/24):** Main network for VXLAN traffic ingress
*   **vxlan-processing (172.20.1.0/24):** Connects VXLAN-PROCESSOR to SECURITY-PROCESSOR
*   **processing-destination (172.20.2.0/24):** Connects SECURITY-PROCESSOR to DESTINATION

### Project Structure

The project is organized with the following key components:

*   `README.md`: Provides a comprehensive overview of the project.
*   `config.json`: Centralized configuration for the 3-container architecture.
*   `src/main.py`: The main command-line interface for managing the setup, running tests, and debugging.
*   `src/utils/`: Contains Python modules for container management, network setup, and traffic generation.
*   `src/containers/`: Contains VPP configuration scripts and Dockerfiles for each container type.

### Use Cases

This project is a practical demonstration of several cloud networking scenarios, including:

*   **Multi-Cloud Connectivity:** Establishing secure tunnels between different cloud environments (e.g., AWS and GCP).
*   **Network Function Virtualization (NFV):** Chaining together modular network services.
*   **Microservices Networking:** Optimizing the data plane for service meshes.
*   **Edge Computing:** High-performance packet processing at the network edge.
*   **Security Gateway:** Combining NAT and IPsec for enterprise-grade traffic security.

It is a valuable resource for anyone interested in advanced cloud networking, NFV, and network security.

### Architecture

```
┌─────────────┐    ┌─────────────────────────────────────┐    ┌─────────────┐
│VXLAN-PROC   │───▶│        SECURITY-PROCESSOR           │───▶│DESTINATION  │
│172.20.0.10  │    │         172.20.1.20                 │    │172.20.2.20  │
│   Receives  │    │┌─────────┬─────────┬─────────────┐   │    │ TAP Bridge  │
│VXLAN Traffic│    ││  NAT44  │ IPsec   │Fragmentation│   │    │  10.0.3.1   │
│ UDP:4789    │    ││10.10.10.│AES-GCM  │  MTU 1400   │   │    │  Receives   │
│             │    ││10→172.20││ -128    │ IP Fragments│   │    │& Captures   │
│ Decap VNI   │    ││ .2.10   │ESP Tunn.│Large Packets│   │    │Final Packets│
│    100      │    │└─────────┴─────────┴─────────────┘   │    │             │
└─────────────┘    └─────────────────────────────────────┘    └─────────────┘
        ▲                              │                                │
        │                       Consolidated                      TAP Interface
        │                      Security Functions                 Packet Capture
        │                                                        & Linux Bridge
┌─────────────┐
│   Traffic   │
│ Generator   │  
│ Python/Scapy│
│ Large Pkts  │
│ 8KB Payload │
└─────────────┘
```

### Processing Flow

1. **VXLAN-PROCESSOR (172.20.0.10)**: Receives VXLAN-encapsulated UDP traffic on port 4789 and decapsulates VXLAN packets (VNI 100) to extract inner IP packets
2. **SECURITY-PROCESSOR (172.20.1.20)**: Consolidated processing that performs:
   - NAT44 translation of inner packet addresses (10.10.10.10:2055 → 172.20.2.10:2055)
   - IPsec ESP encryption with AES-GCM-128 in an IPIP tunnel (172.20.1.20 → 172.20.2.20)
   - IP fragmentation for large packets exceeding 1400 byte MTU
3. **DESTINATION (172.20.2.20)**: Final destination with TAP interface bridge (10.0.3.1/24) for packet capture and Linux integration

## Quick Start

### Prerequisites

- **Ubuntu 20.04+** or similar Linux distribution
- **Docker 20.10+** with docker-compose
- **Python 3.8+** with pip
- **Root access** (required for network configuration)
- **4GB+ RAM** required for optimized 3-container VPP setup

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd vpp_chain

# Install Python dependencies
sudo apt update
sudo apt install -y python3-pip python3-scapy
pip3 install docker

# Verify requirements
sudo python3 src/main.py --help
```

### Basic Usage

```bash
# 1. Setup the multi-container chain
sudo python3 src/main.py setup

# 2. Verify the setup
sudo python3 src/main.py status

# 3. Run traffic tests
sudo python3 src/main.py test

# 4. Debug individual containers
sudo python3 src/main.py debug chain-vxlan "show vxlan tunnel"

# 5. Clean up when done
sudo python3 src/main.py cleanup
```

## Detailed Commands

### Setup and Management

```bash
# Setup with forced rebuild
sudo python3 src/main.py setup --force

# Show current chain status
python3 src/main.py status

# Monitor chain for 2 minutes
python3 src/main.py monitor --duration 120
```

### Testing

```bash
# Run full test suite (connectivity + traffic)
sudo python3 src/main.py test

# Test only connectivity
sudo python3 src/main.py test --type connectivity  

# Test only traffic generation
sudo python3 src/main.py test --type traffic
```

### Debugging

```bash
# Debug VXLAN decapsulation
sudo python3 src/main.py debug vxlan-processor "show vxlan tunnel"

# Check consolidated security processing
sudo python3 src/main.py debug security-processor "show nat44 sessions"
sudo python3 src/main.py debug security-processor "show ipsec sa"
sudo python3 src/main.py debug security-processor "show ipip tunnel"

# Check destination and packet capture
sudo python3 src/main.py debug destination "show interface"
sudo python3 src/main.py debug destination "show trace"

# View packet traces
sudo python3 src/main.py debug vxlan-processor "show trace"
```

## Container Architecture

### Container Specifications

| Container | Role | Networks | Key Configuration |
|-----------|------|----------|-------------------|
| **vxlan-processor** | VXLAN Decapsulation | external-traffic, vxlan-processing | Receives VXLAN on 172.20.0.10:4789, decaps VNI 100 |
| **security-processor** | Security Functions | vxlan-processing, processing-destination | NAT44 + IPsec ESP + Fragmentation (172.20.1.20) |
| **destination** | Packet Capture | processing-destination | TAP interface bridge to 10.0.3.1/24, packet capture |

### Network Topology

```
Networks:
├── external-traffic (172.20.0.0/24)        # VXLAN traffic ingress
├── vxlan-processing (172.20.1.0/24)        # VXLAN → Security Processing
└── processing-destination (172.20.2.0/24)  # Security → Destination
```

### Architecture Benefits

**Consolidated 3-Container Design:**
- 50% reduction in resource usage (from 6 to 3 containers)
- Simplified network topology and debugging  
- Logical separation: Network Processing | Security Processing | Destination
- Maintained functionality with improved efficiency
- Reduced inter-container communication overhead

## Project Structure

```
vpp_chain/
├── README.md                       # This comprehensive guide
├── config.json                    # Centralized network and container configuration
├── CLAUDE.md                      # Claude Code guidance documentation
├── quick-start.sh                 # Quick setup and test script
├── src/
│   ├── main.py                    # Main CLI entry point
│   ├── utils/                     # Python utility modules
│   │   ├── __init__.py
│   │   ├── logger.py             # Logging and output formatting
│   │   ├── container_manager.py  # Docker container management
│   │   ├── network_manager.py    # Network setup and testing
│   │   ├── config_manager.py     # Configuration management
│   │   └── traffic_generator.py  # Traffic generation and testing
│   └── containers/               # Container configurations
│       ├── vxlan-config.sh       # VXLAN processor configuration
│       ├── security-config.sh    # Security processor configuration  
│       ├── destination-config.sh # Destination configuration
│       ├── Dockerfile.vxlan      # VXLAN processor container
│       ├── Dockerfile.security   # Security processor container
│       └── Dockerfile.destination # Destination container
└── docs/                         # Additional documentation
    └── manual_test_guide.md      # Detailed testing procedures
```

## Troubleshooting

### Common Issues and Solutions

#### High CPU Usage on TAP Interface (destination)
The TAP interface in the destination container may consume high CPU due to polling mode:

```bash
# Check TAP interface CPU usage
docker exec destination top -p $(pgrep vpp)

# Solution: Optimize TAP interface settings
docker exec destination vppctl set interface rx-mode tap0 interrupt
```

#### VPP Packet Drops and Test Failures
VPP's high-performance architecture can cause "Low success rate" errors:

**Why this happens:**
- VPP bypasses the Linux kernel network stack for performance
- Direct hardware access can cause standard tools to miss packets
- VPP uses its own packet buffers, separate from kernel buffers

**Diagnostic commands:**
```bash
# Check detailed drop reasons
docker exec vxlan-processor vppctl show errors

# Check interface statistics
for container in vxlan-processor security-processor destination; do
  echo "=== $container Interface Stats ==="
  docker exec $container vppctl show interface | grep -E "(rx packets|tx packets|drops)"
done

# Check VPP traces
docker exec vxlan-processor vppctl show trace
```

**Solutions:**
1. Use UDP connectivity tests instead of ICMP ping (VPP drops ping by design)
2. Increase buffer sizes and optimize network settings
3. Use the enhanced traffic generator with retry logic

#### Container Health Issues
```bash
# Verify all containers are running and VPP is responsive
for container in vxlan-processor security-processor destination; do
  echo "Checking $container..."
  docker exec $container vppctl show version >/dev/null 2>&1 && echo "OK" || echo "FAILED"
done
```

#### Network Connectivity Problems
```bash
# Test UDP connectivity between container pairs (recommended over ping)
echo "test" | docker exec -i vxlan-processor nc -u -w 1 172.20.1.20 2000

# Check VPP routing tables
docker exec vxlan-processor vppctl show ip fib | grep -E "172.20"

# Verify ARP resolution
docker exec vxlan-processor vppctl show ip neighbors
```

### Advanced Testing Procedures

For comprehensive testing, refer to the `docs/manual_test_guide.md` which includes:

- Infrastructure validation (container status, VPP health, interface status)
- Layer 3 connectivity testing with expected results
- UDP traffic flow testing (recommended method for VPP)
- VPP routing table analysis
- Specialized function validation (VXLAN, NAT44, IPsec, fragmentation)
- Packet tracing and traffic analysis
- Troubleshooting commands with interpretation guidance

#### Key Testing Commands

```bash
# 1. Basic health check
sudo python3 src/main.py status

# 2. Connectivity test
sudo python3 src/main.py test --type connectivity

# 3. Traffic test with enhanced handling
sudo python3 src/main.py test --type traffic

# 4. Debug specific container
sudo python3 src/main.py debug vxlan-processor "show vxlan tunnel"

# 5. Manual UDP connectivity test (most reliable for VPP)
timeout 2 docker exec vxlan-processor nc -l -u -p 2000 &
echo "test" | timeout 2 docker exec -i vxlan-processor nc -u -w 1 172.20.1.20 2000
```

### Performance Optimization

#### System-level Optimizations
```bash
# Increase buffer sizes for better VPP performance
echo 'net.core.rmem_default = 262144' >> /etc/sysctl.conf
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf  
echo 'net.core.wmem_default = 262144' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
sysctl -p
```

#### VPP Configuration Optimizations
```bash
# Enable promiscuous mode for better packet reception
docker exec vxlan-processor vppctl set interface promiscuous on host-eth0

# Optimize buffer allocation
docker exec vxlan-processor vppctl set interface rx-mode host-eth0 polling

# Set larger MTU for jumbo frame support
docker exec vxlan-processor vppctl set interface mtu packet 9000 host-eth0
```

## Detailed Network Architecture

### Physical and Logical Interface Mappings

Each container runs VPP with AF_PACKET interfaces mapped to Docker bridge networks:

```
Container Network Architecture:
┌─────────────────────────────────────────────────────────────┐
│                    HOST LINUX SYSTEM                        │
│  Docker Bridge Networks:                                    │
│  ├── external-traffic      (172.20.0.0/24, GW: 172.20.0.1) │
│  ├── vxlan-processing      (172.20.1.0/24, GW: 172.20.1.1) │
│  └── processing-destination (172.20.2.0/24, GW: 172.20.2.1) │
└─────────────────────────────────────────────────────────────┘
```

### Complete Packet Transformation Flow

1. **Traffic Generation → VXLAN-PROCESSOR**: VXLAN(VNI=100)/IP(10.10.10.5→10.10.10.10)/UDP(2055)
2. **VXLAN-PROCESSOR → SECURITY-PROCESSOR**: Decapsulated inner packet IP(10.10.10.5→10.10.10.10)/UDP(2055)
3. **SECURITY-PROCESSOR (NAT44)**: NAT-translated IP(10.10.10.5→172.20.2.10)/UDP(2055)
4. **SECURITY-PROCESSOR (IPsec)**: Encrypted IP(172.20.1.20→172.20.2.20)/ESP(encrypted_payload)
5. **SECURITY-PROCESSOR (Fragmentation)**: Fragmented encrypted packets (≤1400 bytes each)
6. **DESTINATION**: Reassembled packets via 10.0.3.1/24 TAP bridge to Linux stack

## Use Cases

### Cloud Networking Scenarios

1. **Multi-Cloud Connectivity**: Secure tunneling between AWS and GCP
2. **Network Function Virtualization (NFV)**: Modular network service chaining
3. **Microservices Networking**: Service mesh data plane optimization
4. **Edge Computing**: High-performance packet processing at network edge
5. **Security Gateway**: Combined NAT + IPsec processing for enterprise traffic

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make changes and test thoroughly
4. Commit with clear messages: `git commit -m "feat: add new feature"`
5. Push and create a pull request

---

**Built for high-performance networking and cloud-native architectures**