# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a VPP (Vector Packet Processing) multi-container chain project that implements a high-performance network processing pipeline. The architecture demonstrates VXLAN decapsulation → NAT translation → IPsec encryption → packet fragmentation in a modular Docker-based setup using Python orchestration.

### Chain Architecture
```
INGRESS → VXLAN → NAT44 → IPSEC → FRAGMENT → GCP
```

### Core Python Architecture
- **main.py**: CLI entry point with argparse-based command routing to VPPChainManager
- **utils/container_manager.py**: Docker lifecycle, VPP configuration, debugging via subprocess
- **utils/network_manager.py**: Network setup and connectivity testing between containers
- **utils/traffic_generator.py**: Scapy-based traffic generation and validation
- **utils/logger.py**: Structured logging with success/error/warning formatting

## Key Commands

### Setup and Management
- **Setup environment**: `sudo python3 src/main.py setup`
- **Setup with rebuild**: `sudo python3 src/main.py setup --force`
- **Check status**: `python3 src/main.py status`
- **Clean up**: `sudo python3 src/main.py cleanup`

### Testing and Debugging
- **Run all tests**: `sudo python3 src/main.py test`
- **Test connectivity only**: `sudo python3 src/main.py test --type connectivity`
- **Test traffic only**: `sudo python3 src/main.py test --type traffic`
- **Debug container**: `sudo python3 src/main.py debug <container-name> "<vpp-command>"`
- **Monitor chain**: `python3 src/main.py monitor --duration 120`

### Comprehensive Validation Framework
- **Complete validation**: `./comprehensive-validation.sh` - Novel-like storytelling logs
- **Container monitoring**: `src/containers/<container>/monitor-*.sh` - Detailed per-container analysis
- **Packet capture**: `src/containers/gcp/capture-packets.sh` - Destination packet capture
- **Traffic analysis**: `src/containers/gcp/analyze-packets.sh` - Packet analysis with statistics

#### Validation Features
- **Docker Compose validation**: Syntax, networks, service dependencies
- **Container validation**: Health checks, VPP responsiveness, resource usage
- **VPP configuration validation**: Interfaces, plugins, memory, container-specific features
- **Connectivity validation**: Inter-container networking across all segments
- **Tunnel validation**: VXLAN and IPsec tunnel status and statistics
- **Traffic tracing**: Packet traces at every entry/exit point with detailed analysis
- **Novel-like logging**: Color-coded storytelling that explains the complete packet journey

### Container Commands
- **Start containers**: `docker-compose up -d`
- **Stop containers**: `docker-compose down --volumes --remove-orphans`
- **Build base image**: `docker build -t vpp-chain-base:latest -f src/containers/Dockerfile.base .`

### VPP Debug Commands
Example debugging commands for each container:
- VXLAN: `sudo python3 src/main.py debug chain-vxlan "show vxlan tunnel"`
- NAT: `sudo python3 src/main.py debug chain-nat "show nat44 sessions"`
- IPsec: `sudo python3 src/main.py debug chain-ipsec "show ipsec sa"`
- Fragment: `sudo python3 src/main.py debug chain-fragment "show interface"`

### Development Commands
- **Manual VPP CLI access**: `docker exec -it <container> vppctl`
- **View container logs**: `docker logs <container>`
- **Test Python components**: Run individual utils modules for debugging

## Architecture Components

### Container Chain
1. **chain-ingress** (192.168.10.2): Receives VXLAN traffic on UDP:4789
2. **chain-vxlan** (10.1.1.2→10.1.2.1): Decapsulates VXLAN VNI 100 packets
3. **chain-nat** (10.1.2.2→10.1.3.1): NAT44 translation (10.10.10.10:2055 → 10.0.3.1:2055)
4. **chain-ipsec** (10.1.3.2→10.1.4.1): ESP AES-GCM-128 encryption
5. **chain-fragment** (10.1.4.2→192.168.10.4): IP fragmentation (MTU 1400)
6. **chain-gcp** (192.168.10.3): Destination endpoint

### Network Segments
- **underlay** (192.168.10.0/24): Main network for ingress/egress
- **chain-1-2** (10.1.1.0/24): Ingress → VXLAN
- **chain-2-3** (10.1.2.0/24): VXLAN → NAT
- **chain-3-4** (10.1.3.0/24): NAT → IPsec
- **chain-4-5** (10.1.4.0/24): IPsec → Fragment

### Code Structure
```
src/
├── main.py                     # CLI entry point with VPPChainManager class
├── utils/
│   ├── container_manager.py    # ContainerManager with CONTAINERS config array
│   ├── network_manager.py      # NetworkManager for connectivity testing
│   ├── traffic_generator.py    # TrafficGenerator using Scapy for packet crafting
│   └── logger.py              # Logging with log_success/log_error helpers
├── containers/                 # Container-specific files organized by container
│   ├── Dockerfile.base         # Base VPP container image
│   ├── ingress/               # Ingress container files
│   │   ├── README.md          # Container documentation
│   │   ├── ingress-config.sh  # VPP configuration script
│   │   ├── Dockerfile.ingress # Specialized container build (optional)
│   │   └── monitor-ingress.sh # Container monitoring script
│   ├── vxlan/                 # VXLAN container files
│   │   ├── README.md          # Container documentation
│   │   ├── vxlan-config.sh    # VPP configuration script
│   │   ├── vxlan-advanced.conf# Advanced VXLAN configuration examples
│   │   └── monitor-vxlan.sh   # Container monitoring script
│   ├── nat/                   # NAT container files
│   │   ├── README.md          # Container documentation
│   │   ├── nat-config.sh      # VPP configuration script
│   │   ├── nat-advanced.conf  # Advanced NAT configuration examples
│   │   ├── Dockerfile.nat     # Specialized container build
│   │   └── monitor-nat.sh     # Container monitoring script
│   ├── ipsec/                 # IPsec container files
│   │   ├── README.md          # Container documentation
│   │   ├── ipsec-config.sh    # VPP configuration script
│   │   ├── ipsec-advanced.conf# Advanced IPsec configuration examples
│   │   └── monitor-ipsec.sh   # Container monitoring script
│   ├── fragment/              # Fragment container files
│   │   ├── README.md          # Container documentation
│   │   ├── fragment-config.sh # VPP configuration script
│   │   ├── fragment-advanced.conf # Advanced fragmentation examples
│   │   ├── Dockerfile.fragment# Specialized container build
│   │   └── monitor-fragmentation.sh # Container monitoring script
│   └── gcp/                   # GCP endpoint container files
│       ├── README.md          # Container documentation
│       ├── gcp-config.sh      # VPP configuration script
│       ├── gcp-advanced.conf  # Advanced endpoint configuration examples
│       ├── Dockerfile.gcp     # Specialized container build
│       ├── capture-packets.sh # Packet capture script
│       └── analyze-packets.sh # Packet analysis script
└── configs/                   # Common VPP configuration files
    ├── startup.conf           # VPP startup configuration (shared)
    └── start-vpp.sh          # VPP startup script (shared)
```

## Development Notes

### Prerequisites
- Ubuntu 20.04+ with Docker 20.10+
- Python 3.8+ with Scapy
- Root privileges required for most operations
- 8GB+ RAM recommended

### VPP Configuration Pattern
Each container follows this pattern:
1. Create host interfaces for inter-container networking
2. Set IP addresses and bring interfaces up
3. Configure specific VPP features (VXLAN, NAT, IPsec, etc.)
4. Set up routing between interfaces
5. Enable packet tracing for debugging

### Critical VPP Configuration Notes
- **DPDK no-pci requirement**: VPP startup.conf must include `no-pci` under dpdk section to prevent VPP from claiming all host interfaces, which would break VM/container management connectivity
- This project uses host interfaces instead of DPDK interfaces for container networking
- All VPP configs use vppctl commands for runtime configuration rather than startup.conf

### Sample VPP startup.conf
Complete startup.conf template for AWS/cloud deployments:
```
# aws-startup.conf
unix {
  nodaemon
  log /var/log/vpp/vpp.log
  full-coredump
  cli-listen /run/vpp/cli.sock
  gid vpp
}

dpdk {
  no-pci
}

plugins {
  plugin default { enable }
  plugin crypto_native_plugin.so { enable }
  plugin ipsec_plugin.so { enable }
  plugin af_packet_plugin.so { enable }
  plugin vxlan_plugin.so { enable }
  plugin nat_plugin.so { enable }
}

logging {
  default-log-level debug
}
```
Key points:
- `no-pci` prevents interface takeover
- Essential plugins enabled for VXLAN, NAT, IPsec functionality
- Debug logging for troubleshooting
- Unix socket for vppctl access

### Container Orchestration
- Containers start with staggered delays (sleep 8, 10, 12, 14, 16, 18)
- All containers use shared Dockerfile.base with VPP pre-installed
- VPP configs mounted as read-only volumes at /vpp-config
- Privileged mode + NET_ADMIN/SYS_ADMIN capabilities required for VPP
- Each container runs start-vpp.sh which starts VPP and waits for readiness

### Container Management Details
- ContainerManager class handles lifecycle via subprocess calls to docker-compose
- Container definitions stored in CONTAINERS array with network/IP mappings
- Debug operations execute vppctl commands via docker exec
- Health checks verify VPP CLI responsiveness before proceeding

### Testing Framework
- VPPChainManager orchestrates setup/test/cleanup workflow
- Connectivity tests verify inter-container networking via NetworkManager
- Traffic tests use TrafficGenerator with Scapy to create VXLAN packets
- Monitor mode provides real-time chain health with configurable duration
- All operations require root privileges due to VPP networking requirements

### Development Workflow
1. Use `python3 src/main.py setup` to build and start entire chain
2. Test connectivity and traffic with `test` command
3. Debug individual containers with specific VPP commands
4. Use `monitor` for ongoing health monitoring
5. Clean up with `cleanup` command to remove containers/networks