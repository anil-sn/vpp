# VPP Multi-Container Chain: VXLAN → NAT → IPsec → Fragmentation

[![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)](https://python.org)
[![Docker](https://img.shields.io/badge/Docker-20.10+-blue.svg)](https://docker.com)
[![VPP](https://img.shields.io/badge/VPP-22.02+-green.svg)](https://fd.io)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

This project showcases a high-performance, modular network processing pipeline using Vector Packet Processing (VPP) distributed across multiple Docker containers. It demonstrates a sequence of advanced networking functions: VXLAN decapsulation, Network Address Translation (NAT), IPsec encryption, and packet fragmentation, simulating a real-world cloud networking scenario.

### Architecture and Processing Flow

The architecture consists of a chain of Docker containers, each responsible for a specific network function. Data flows through this chain in the following sequence:

1.  **INGRESS (chain-ingress):** Receives incoming VXLAN-encapsulated UDP traffic on 172.20.0.10:4789
2.  **VXLAN (chain-vxlan):** Decapsulates VXLAN packets targeting VNI 100 to extract inner IP packets
3.  **NAT44 (chain-nat):** Performs network address translation mapping inner packet addresses (10.10.10.10:2055 → 172.20.3.10:2055)
4.  **IPSEC (chain-ipsec):** Encrypts translated packets using ESP with AES-GCM-128 in an IPIP tunnel
5.  **FRAGMENT (chain-fragment):** Fragments packets exceeding MTU of 1400 bytes before final delivery
6.  **GCP (chain-gcp):** Final destination endpoint that receives processed and reassembled packets via TAP interface

### Container and Network Setup

The project uses Python-based container management to orchestrate the containers. Each container is connected to its neighbors in the chain via dedicated Docker networks. The current network topology is as follows:

*   **external-ingress (172.20.0.0/24):** Main network for ingress traffic reception
*   **ingress-vxlan (172.20.1.0/24):** Connects the INGRESS and VXLAN containers
*   **vxlan-nat (172.20.2.0/24):** Connects the VXLAN and NAT containers  
*   **nat-ipsec (172.20.3.0/24):** Connects the NAT and IPsec containers
*   **ipsec-fragment (172.20.4.0/24):** Connects the IPsec and FRAGMENT containers
*   **fragment-gcp (172.20.5.0/24):** Connects the FRAGMENT and GCP containers

### Project Structure

The project is organized with the following key components:

*   `README.md`: Provides a comprehensive overview of the project.
*   `docker-compose.yml`: Defines and configures the multi-container setup.
*   `src/main.py`: The main command-line interface for managing the setup, running tests, and debugging.
*   `src/utils/`: Contains Python modules for container management, network setup, and traffic generation.
*   `src/configs/`: Includes shell scripts for configuring VPP within each container.

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
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   INGRESS   │───▶│   VXLAN     │───▶│    NAT44    │───▶│   IPSEC     │───▶│ FRAGMENT    │───▶│     GCP     │
│ 172.20.0.10 │    │ 172.20.1.20 │    │ 172.20.2.20 │    │ 172.20.3.20 │    │ 172.20.4.20 │    │ 172.20.5.20 │
│   Receives  │    │ Decap VNI   │    │ 10.10.10.10 │    │ AES-GCM-128 │    │  MTU 1400   │    │ TAP Bridge  │
│VXLAN Traffic│    │    100      │    │→172.20.3.10 │    │ Encryption  │    │ IP Fragments│    │  10.0.3.1   │
│ UDP:4789    │    │ UDP:4789    │    │  Port:2055  │    │ ESP Tunnel  │    │ Large Pkts  │    │  Receives   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
        ▲                    │                    │                    │                    │                    │
        │              VXLAN Decap         NAT Translation      IPsec ESP           IP Fragmentation    TAP Interface
        │              Strips outer        Translates src       Encrypts payload    Splits >MTU packets  Bridge to Linux
        │              headers             IP:PORT mapping      with AES-GCM-128    into fragments       for capture
        │
┌─────────────┐
│   Traffic   │
│ Generator   │  
│ Python/Scapy│
│ Large Pkts  │
│ 8KB Payload │
└─────────────┘
```

### Processing Flow

1. **INGRESS (172.20.0.10)**: Receives VXLAN-encapsulated UDP traffic and forwards to VXLAN container
2. **VXLAN (172.20.1.20)**: Decapsulates VXLAN packets (VNI 100) to extract inner IP packets  
3. **NAT44 (172.20.2.20)**: Translates inner packet addresses (10.10.10.10:2055 → 172.20.3.10:2055)
4. **IPSEC (172.20.3.20)**: Encrypts packets using ESP with AES-GCM-128 in an IPIP tunnel
5. **FRAGMENT (172.20.4.20)**: Fragments large packets (>1400 MTU) before final delivery
6. **GCP (172.20.5.20)**: Final destination with TAP interface bridge (10.0.3.1) for packet capture

## Quick Start

### Prerequisites

- **Ubuntu 20.04+** or similar Linux distribution
- **Docker 20.10+** with docker-compose
- **Python 3.8+** with pip
- **Root access** (required for network configuration)
- **8GB+ RAM** recommended for VPP containers

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
sudo python3 src/main.py debug chain-vxlan "show vxlan tunnel"

# Check NAT sessions
sudo python3 src/main.py debug chain-nat "show nat44 sessions"

# Verify IPsec SAs
sudo python3 src/main.py debug chain-ipsec "show ipsec sa"

# Check interface statistics
sudo python3 src/main.py debug chain-fragment "show interface"

# View packet traces
sudo python3 src/main.py debug chain-vxlan "show trace"
```

## Container Architecture

### Container Specifications

| Container | Role | Networks | Key Configuration |
|-----------|------|----------|-------------------|
| **chain-ingress** | VXLAN Reception | external-ingress, ingress-vxlan | Receives VXLAN on 172.20.0.10:4789 |
| **chain-vxlan** | VXLAN Decapsulation | ingress-vxlan, vxlan-nat | Decaps VNI 100, forwards inner IP |
| **chain-nat** | NAT Translation | vxlan-nat, nat-ipsec | Maps 10.10.10.10:2055 → 172.20.3.10:2055 |
| **chain-ipsec** | IPsec Encryption | nat-ipsec, ipsec-fragment | ESP AES-GCM-128 encryption |
| **chain-fragment** | IP Fragmentation | ipsec-fragment, fragment-gcp | MTU 1400, fragments large packets |
| **chain-gcp** | Final Destination | fragment-gcp | TAP interface bridge to 10.0.3.1/24 |

### Network Topology

```
Networks:
├── external-ingress (172.20.0.0/24)    # Main network for ingress traffic
├── ingress-vxlan (172.20.1.0/24)       # Ingress → VXLAN
├── vxlan-nat (172.20.2.0/24)           # VXLAN → NAT
├── nat-ipsec (172.20.3.0/24)           # NAT → IPsec
├── ipsec-fragment (172.20.4.0/24)      # IPsec → Fragment
└── fragment-gcp (172.20.5.0/24)        # Fragment → GCP
```

## Project Structure

```
vpp_chain/
├── README.md                       # This comprehensive guide
├── config.json                    # Network and container configuration
├── src/
│   ├── main.py                    # Main CLI entry point
│   ├── utils/                     # Python utility modules
│   │   ├── __init__.py
│   │   ├── logger.py             # Logging and output formatting
│   │   ├── container_manager.py  # Docker container management
│   │   ├── network_manager.py    # Network setup and testing
│   │   └── traffic_generator.py  # Traffic generation and testing
│   └── containers/               # Container-specific configurations
│       ├── ingress/              # VXLAN reception container
│       ├── vxlan/               # VXLAN decapsulation container
│       ├── nat/                 # NAT44 translation container
│       ├── ipsec/               # IPsec encryption container
│       ├── fragment/            # IP fragmentation container
│       ├── gcp/                 # Final destination container
│       └── Dockerfile.base      # Base container image
├── docs/                        # Additional documentation
└── VPP_CHAIN_MANUAL_TEST_GUIDE.md # Detailed testing procedures
```

## Troubleshooting

### Common Issues and Solutions

#### High CPU Usage on TAP Interface (chain-gcp)
The TAP interface in the chain-gcp container may consume high CPU due to polling mode:

```bash
# Check TAP interface CPU usage
docker exec chain-gcp top -p $(pgrep vpp)

# Solution: Optimize TAP interface settings
docker exec chain-gcp vppctl set interface rx-mode tap0 interrupt
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
docker exec chain-vxlan vppctl show errors

# Check interface statistics
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "=== $container Interface Stats ==="
  docker exec $container vppctl show interface | grep -E "(rx packets|tx packets|drops)"
done

# Check VPP traces
docker exec chain-vxlan vppctl show trace
```

**Solutions:**
1. Use UDP connectivity tests instead of ICMP ping (VPP drops ping by design)
2. Increase buffer sizes and optimize network settings
3. Use the enhanced traffic generator with retry logic

#### Container Health Issues
```bash
# Verify all containers are running and VPP is responsive
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "Checking $container..."
  docker exec $container vppctl show version >/dev/null 2>&1 && echo "✅ OK" || echo "❌ FAILED"
done
```

#### Network Connectivity Problems
```bash
# Test UDP connectivity between container pairs (recommended over ping)
echo "test" | docker exec -i chain-ingress nc -u -w 1 172.20.1.20 2000

# Check VPP routing tables
docker exec chain-vxlan vppctl show ip fib | grep -E "172.20"

# Verify ARP resolution
docker exec chain-vxlan vppctl show ip neighbors
```

### Advanced Testing Procedures

For comprehensive testing, refer to the `/home/asrirang/code/vpp/vpp_chain/VPP_CHAIN_MANUAL_TEST_GUIDE.md` which includes:

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
sudo python3 src/main.py debug chain-vxlan "show vxlan tunnel"

# 5. Manual UDP connectivity test (most reliable for VPP)
timeout 2 docker exec chain-vxlan nc -l -u -p 2000 &
echo "test" | timeout 2 docker exec -i chain-ingress nc -u -w 1 172.20.1.20 2000
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
docker exec chain-ingress vppctl set interface promiscuous on host-eth0

# Optimize buffer allocation
docker exec chain-ingress vppctl set interface rx-mode host-eth0 polling

# Set larger MTU for jumbo frame support
docker exec chain-ingress vppctl set interface mtu packet 9000 host-eth0
```

## Detailed Network Architecture

### Physical and Logical Interface Mappings

Each container runs VPP with AF_PACKET interfaces mapped to Docker bridge networks:

```
Container Network Architecture:
┌─────────────────────────────────────────────────────────────┐
│                    HOST LINUX SYSTEM                        │
│  Docker Bridge Networks:                                    │
│  ├── external-ingress    (172.20.0.0/24, GW: 172.20.0.1)  │
│  ├── ingress-vxlan       (172.20.1.0/24, GW: 172.20.1.1)  │
│  ├── vxlan-nat           (172.20.2.0/24, GW: 172.20.2.1)  │
│  ├── nat-ipsec           (172.20.3.0/24, GW: 172.20.3.1)  │
│  ├── ipsec-fragment      (172.20.4.0/24, GW: 172.20.4.1)  │
│  └── fragment-gcp        (172.20.5.0/24, GW: 172.20.5.1)  │
└─────────────────────────────────────────────────────────────┘
```

### Complete Packet Transformation Flow

1. **Traffic Generation → INGRESS**: VXLAN(VNI=100)/IP(10.10.10.5→10.10.10.10)/UDP(2055)
2. **INGRESS → VXLAN**: Forwards VXLAN packet unchanged
3. **VXLAN → NAT**: Decapsulated inner packet IP(10.10.10.5→10.10.10.10)/UDP(2055)
4. **NAT → IPSEC**: NAT-translated IP(10.10.10.5→172.20.3.10)/UDP(2055)
5. **IPSEC → FRAGMENT**: Encrypted IP(172.20.3.20→172.20.4.20)/ESP(encrypted_payload)
6. **FRAGMENT → GCP**: Fragmented encrypted packets (≤1400 bytes each)
7. **GCP TAP Interface**: Reassembled packets via 10.0.3.1/24 bridge to Linux stack

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