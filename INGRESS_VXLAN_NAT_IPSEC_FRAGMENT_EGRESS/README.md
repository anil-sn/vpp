# VPP Multi-Container Chain: VXLAN → NAT → IPsec → Fragmentation

[![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)](https://python.org)
[![Docker](https://img.shields.io/badge/Docker-20.10+-blue.svg)](https://docker.com)
[![VPP](https://img.shields.io/badge/VPP-22.02+-green.svg)](https://fd.io)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🎯 Overview

This project implements a high-performance, modular network processing pipeline using Vector Packet Processing (VPP) across multiple Docker containers. The architecture demonstrates advanced networking concepts including VXLAN decapsulation, NAT translation, IPsec encryption, and packet fragmentation in a real-world cloud networking scenario.

### 🏗️ Architecture

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   INGRESS   │───▶│   VXLAN     │───▶│    NAT44    │───▶│   IPSEC     │───▶│ FRAGMENT    │───▶ [GCP]
│ 192.168.1.2 │    │ Decap VNI   │    │ 10.10.10.10 │    │ AES-GCM-128 │    │  MTU 1400   │
│   Receives  │    │    100      │    │ → 10.0.3.1  │    │ Encryption  │    │ IP Fragments│
│VXLAN Traffic│    │ UDP:4789    │    │  Port:2055  │    │ ESP Tunnel  │    │ Large Pkts  │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
        ▲                    │                    │                    │                    │
        │              VXLAN Decap         NAT Translation      IPsec ESP           IP Fragmentation
        │              Strips outer        Translates src       Encrypts payload    Splits >MTU packets
        │              headers             IP:PORT mapping      with AES-GCM-128    into fragments
        │
┌─────────────┐
│   Traffic   │
│ Generator   │  
│ Python/Scapy│
│ Large Pkts  │
└─────────────┘
```

### 🔄 Processing Flow

1. **INGRESS**: Receives VXLAN-encapsulated UDP traffic from external sources
2. **VXLAN**: Decapsulates VXLAN packets (VNI 100) to extract inner IP packets  
3. **NAT44**: Translates inner packet addresses (10.10.10.10:2055 → 10.0.3.1:2055)
4. **IPSEC**: Encrypts packets using ESP with AES-GCM-128 in an IPIP tunnel
5. **FRAGMENT**: Fragments large packets (>1400 MTU) before final delivery
6. **GCP**: Destination endpoint that receives processed and fragmented packets

## 🚀 Quick Start

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
cd vpp-ipsec-udp-vxlan

# Install Python dependencies
sudo apt update
sudo apt install -y python3-pip python3-scapy
pip3 install docker-compose

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

## 📋 Detailed Commands

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

## 🐳 Container Architecture

### Container Specifications

| Container | Role | Networks | Key Configuration |
|-----------|------|----------|-------------------|
| **chain-ingress** | VXLAN Reception | underlay, chain-1-2 | Receives VXLAN on 192.168.1.2:4789 |
| **chain-vxlan** | VXLAN Decapsulation | chain-1-2, chain-2-3 | Decaps VNI 100, forwards inner IP |
| **chain-nat** | NAT Translation | chain-2-3, chain-3-4 | Maps 10.10.10.10:2055 → 10.0.3.1:2055 |
| **chain-ipsec** | IPsec Encryption | chain-3-4, chain-4-5 | ESP AES-GCM-128 encryption |
| **chain-fragment** | IP Fragmentation | chain-4-5, underlay | MTU 1400, fragments large packets |
| **chain-gcp** | Destination | underlay | Receives final processed packets |

### Network Topology

```
Networks:
├── underlay (192.168.1.0/24)     # Main network for ingress/egress
├── chain-1-2 (10.1.1.0/24)      # Ingress → VXLAN
├── chain-2-3 (10.1.2.0/24)      # VXLAN → NAT
├── chain-3-4 (10.1.3.0/24)      # NAT → IPsec
└── chain-4-5 (10.1.4.0/24)      # IPsec → Fragment
```

## 📁 Project Structure

```
vpp-ipsec-udp-vxlan/
├── README.md                       # This comprehensive guide
├── docker-compose.yml             # Container orchestration
├── src/
│   ├── main.py                    # Main CLI entry point
│   ├── utils/                     # Python utility modules
│   │   ├── __init__.py
│   │   ├── logger.py             # Logging and output formatting
│   │   ├── container_manager.py  # Docker container management
│   │   ├── network_manager.py    # Network setup and testing
│   │   └── traffic_generator.py  # Traffic generation and testing
│   ├── containers/
│   │   └── Dockerfile.base       # Base container image
│   └── configs/                   # VPP configuration scripts
│       ├── ingress-config.sh
│       ├── vxlan-config.sh
│       ├── nat-config.sh
│       ├── ipsec-config.sh
│       ├── fragment-config.sh
│       └── gcp-config.sh
├── tests/                         # Test cases and validation
├── docs/                         # Additional documentation
└── legacy-backup/                # Legacy single-container files
```

## 🎯 Use Cases

### Cloud Networking Scenarios

1. **Multi-Cloud Connectivity**: Secure tunneling between AWS and GCP
2. **Network Function Virtualization (NFV)**: Modular network service chaining
3. **Microservices Networking**: Service mesh data plane optimization
4. **Edge Computing**: High-performance packet processing at network edge
5. **Security Gateway**: Combined NAT + IPsec processing for enterprise traffic

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make changes and test thoroughly
4. Commit with clear messages: `git commit -m "feat: add new feature"`
5. Push and create a pull request

---

**Built with ❤️ for high-performance networking and cloud-native architectures**