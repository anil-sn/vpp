# Project Overview

This project implements a high-performance, modular network processing pipeline using Vector Packet Processing (VPP) across multiple Docker containers. It demonstrates advanced networking concepts including VXLAN decapsulation, NAT translation, IPsec encryption, and packet fragmentation in a real-world cloud networking scenario.

**Processing Flow:**
1.  **INGRESS**: Receives VXLAN-encapsulated UDP traffic from external sources
2.  **VXLAN**: Decapsulates VXLAN packets (VNI 100) to extract inner IP packets
3.  **NAT44**: Translates inner packet addresses (10.10.10.10:2055 → 10.0.3.1:2055)
4.  **IPSEC**: Encrypts packets using ESP with AES-GCM-128 in an IPIP tunnel
5.  **FRAGMENT**: Fragments large packets (>1400 MTU) before final delivery
6.  **GCP**: Destination endpoint that receives processed and fragmented packets

## Building and Running

### Prerequisites

-   **Ubuntu 20.04+** or similar Linux distribution
-   **Docker 20.10+** with docker-compose
-   **Python 3.8+** with pip
-   **Root access** (required for network configuration)
-   **8GB+ RAM** recommended for VPP containers

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

### Detailed Commands

**Setup and Management**

```bash
# Setup with forced rebuild
sudo python3 src/main.py setup --force

# Show current chain status
python3 src/main.py status

# Monitor chain for 2 minutes
python3 src/main.py monitor --duration 120
```

**Testing**

```bash
# Run full test suite (connectivity + traffic)
sudo python3 src/main.py test

# Test only connectivity
sudo python3 src/main.py test --type connectivity

# Test only traffic generation
sudo python3 src/main.py test --type traffic
```

**Debugging**

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

## Development Conventions

### Contributing

1.  Fork the repository
2.  Create a feature branch: `git checkout -b feature-name`
3.  Make changes and test thoroughly
4.  Commit with clear messages: `git commit -m "feat: add new feature"`
5.  Push and create a pull request

## Project Structure

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
