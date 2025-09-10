# VPP Multi-Container Chain: High-Performance Network Processing Pipeline

[![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)](https://python.org)
[![Docker](https://img.shields.io/badge/Docker-20.10+-blue.svg)](https://docker.com)
[![VPP](https://img.shields.io/badge/VPP-24.10+-green.svg)](https://fd.io)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

This project demonstrates a **high-performance, fully config-driven network processing pipeline** using Vector Packet Processing (VPP) v24.10-release distributed across three specialized Docker containers. The optimized architecture implements **VXLAN decapsulation**, **Network Address Translation (NAT44)**, **IPsec ESP encryption**, and **IP fragmentation** with a **50% resource footprint reduction** while maintaining complete functionality.

### Key Features

- ✅ **Fully Config-Driven**: All network topology, IPs, and settings driven from `config.json`
- ✅ **No Hardcoded Values**: Dynamic configuration loading for complete flexibility
- ✅ **Container-Isolated Networks**: VM management connectivity preserved 
- ✅ **VPP Host Protection**: `no-pci` configuration prevents interface stealing
- ✅ **Consolidated Architecture**: 3-container design vs traditional 6-container setup
- ✅ **End-to-End Testing**: Comprehensive traffic generation and validation
- ✅ **Step-by-Step Debugging**: Per-container packet flow analysis

## Architecture Overview

### Container Processing Pipeline

```
VXLAN-PROCESSOR → SECURITY-PROCESSOR → DESTINATION
     ↓                    ↓                 ↓
VXLAN Decap         NAT44 + IPsec      TAP Interface
 VNI 100           + Fragmentation      & Capture
```

### Three-Container Design

1. **VXLAN-PROCESSOR** (`vxlan-processor`)
   - **Purpose**: VXLAN decapsulation and L2 bridging
   - **Networks**: `external-traffic` (172.20.100.x), `vxlan-processing` (172.20.101.x)
   - **Function**: Receives VXLAN packets (VNI 100), decapsulates inner IP packets

2. **SECURITY-PROCESSOR** (`security-processor`)
   - **Purpose**: Consolidated security processing
   - **Networks**: `vxlan-processing` (172.20.101.x), `processing-destination` (172.20.102.x)
   - **Functions**: NAT44 translation + IPsec ESP AES-GCM-128 + IP fragmentation (MTU 1400)

3. **DESTINATION** (`destination`)
   - **Purpose**: Final packet capture and processing
   - **Networks**: `processing-destination` (172.20.102.x)
   - **Function**: TAP interface bridge (10.0.3.1/24) with packet capture

### Network Topology (Config-Driven)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HOST SYSTEM                                  │
│  Docker Bridge Networks (Isolated from VM Management):              │
│  ├── external-traffic      (172.20.100.0/24, GW: 172.20.100.1)    │
│  ├── vxlan-processing      (172.20.101.0/24, GW: 172.20.101.1)    │
│  └── processing-destination (172.20.102.0/24, GW: 172.20.102.1)    │
│                                                                     │
│  VM Management Network: 10.168.0.x (Unaffected)                   │
└─────────────────────────────────────────────────────────────────────┘
```

### Visual Architecture

```
┌─────────────┐    ┌─────────────────────────────────────┐    ┌─────────────┐
│VXLAN-PROC   │───▶│        SECURITY-PROCESSOR           │───▶│DESTINATION  │
│172.20.100.10│    │┌─────────┬─────────┬─────────────┐   │    │172.20.102.20│
│ Receives    │    ││  NAT44  │ IPsec   │Fragmentation│   │    │ TAP Bridge  │
│VXLAN VNI 100│    ││10.10.10.10│AES-GCM  │  MTU 1400   │   │    │  10.0.3.1   │
│ Decap L2    │    ││→172.20.102.10││ -128    │ IP Fragments│   │    │  Captures   │
│             │    │└─────────┴─────────┴─────────────┘   │    │Final Packets│
└─────────────┘    └─────────────────────────────────────┘    └─────────────┘
        ▲                              │                                │
        │                       Consolidated                      TAP Interface
        │                      Security Functions                 Packet Capture
        │
┌─────────────┐
│   Traffic   │
│ Generator   │  
│ (Config-    │
│  Driven)    │
└─────────────┘
```

## Complete Packet Flow

**End-to-End Processing Chain:**

1. **Traffic Generator** → **VXLAN-PROCESSOR**
   ```
   VXLAN: IP(172.20.100.1→172.20.100.10)/UDP(4789)/VXLAN(VNI=100)/IP(10.10.10.5→10.10.10.10)/UDP(2055)
   ```

2. **VXLAN-PROCESSOR** → **SECURITY-PROCESSOR**
   ```
   Decapsulated: IP(10.10.10.5→10.10.10.10)/UDP(2055) [via L2 bridge]
   ```

3. **SECURITY-PROCESSOR Processing**
   - **NAT44**: `10.10.10.10:2055` → `172.20.102.10:2055`
   - **IPsec**: Encrypt in IPIP tunnel `172.20.101.20` → `172.20.102.20`
   - **Fragmentation**: Split packets > 1400 bytes MTU

4. **SECURITY-PROCESSOR** → **DESTINATION**
   ```
   Encrypted: IP(172.20.101.20→172.20.102.20)/ESP(AES-GCM-128)[fragmented]
   ```

5. **DESTINATION** → **TAP Interface**
   ```
   Final: Decrypted and reassembled packets on 10.0.3.1/24 TAP bridge
   ```

## Quick Start

### Prerequisites

- **Ubuntu 20.04+** or compatible Linux distribution
- **Docker 20.10+** with container runtime
- **Python 3.8+** with pip
- **Root/sudo access** (required for network and container operations)
- **4GB+ RAM** for optimal VPP operation

### Installation

```bash
# Clone repository
git clone <repository-url>
cd vpp_chain

# Install Python dependencies
sudo apt update
sudo apt install -y python3-pip python3-scapy jq
pip3 install docker

# Verify installation
sudo python3 src/main.py --help
```

### Basic Usage

```bash
# 1. Setup the complete chain
sudo python3 src/main.py setup

# 2. Verify all containers and VPP instances
python3 src/main.py status

# 3. Run comprehensive tests
sudo python3 src/main.py test

# 4. Debug specific container
sudo python3 src/main.py debug vxlan-processor "show vxlan tunnel"

# 5. Clean up environment
sudo python3 src/main.py cleanup
```

## Comprehensive Command Reference

### Setup and Management

```bash
# Standard setup
sudo python3 src/main.py setup

# Force rebuild (recommended after config changes)
sudo python3 src/main.py setup --force

# Check status (no root required)
python3 src/main.py status

# Monitor for specified duration
python3 src/main.py monitor --duration 120

# Complete cleanup
sudo python3 src/main.py cleanup
```

### Testing Suite

```bash
# Full test suite (connectivity + traffic)
sudo python3 src/main.py test

# Test only inter-container connectivity
sudo python3 src/main.py test --type connectivity

# Test only end-to-end traffic processing
sudo python3 src/main.py test --type traffic

# Python unit tests
python3 -m unittest discover tests/ -v

# Specific test modules
python3 -m unittest tests.test_integration -v
python3 -m unittest tests.test_container_manager -v
```

### Container Debugging

```bash
# VXLAN Processor debugging
sudo python3 src/main.py debug vxlan-processor "show interface"
sudo python3 src/main.py debug vxlan-processor "show vxlan tunnel" 
sudo python3 src/main.py debug vxlan-processor "show bridge-domain 1 detail"

# Security Processor debugging
sudo python3 src/main.py debug security-processor "show nat44 sessions"
sudo python3 src/main.py debug security-processor "show ipsec sa"
sudo python3 src/main.py debug security-processor "show ipip tunnel"
sudo python3 src/main.py debug security-processor "show interface"

# Destination debugging
sudo python3 src/main.py debug destination "show interface"
sudo python3 src/main.py debug destination "show trace"
sudo python3 src/main.py debug destination "show tap"

# Direct VPP CLI access
docker exec -it vxlan-processor vppctl
docker exec -it security-processor vppctl  
docker exec -it destination vppctl
```

### Advanced Debugging

```bash
# Enable packet tracing
docker exec vxlan-processor vppctl trace add af-packet-input 10
docker exec security-processor vppctl trace add af-packet-input 10
docker exec destination vppctl trace add af-packet-input 10

# View traces
docker exec vxlan-processor vppctl show trace
docker exec security-processor vppctl show trace
docker exec destination vppctl show trace

# Clear traces
docker exec vxlan-processor vppctl clear trace
docker exec security-processor vppctl clear trace
docker exec destination vppctl clear trace

# Interface statistics
for container in vxlan-processor security-processor destination; do
  echo "=== $container Interface Statistics ==="
  docker exec $container vppctl show interface
  echo
done
```

## Configuration Management

### Config-Driven Architecture

**Everything is driven from `config.json`:**

- **Network Topology**: All subnets, gateways, and IP assignments
- **Container Configuration**: Interface mappings, security settings
- **VXLAN Settings**: VNI, tunnel endpoints, decapsulation
- **NAT44 Configuration**: Static mappings, interface assignments
- **IPsec Parameters**: SA configuration, encryption algorithms
- **Traffic Generation**: Source/destination IPs, ports, packet sizes

### Configuration Structure

```json
{
  "default_mode": "gcp",
  "modes": {
    "gcp": {
      "networks": [
        {
          "name": "external-traffic",
          "subnet": "172.20.100.0/24",
          "gateway": "172.20.100.1"
        }
      ],
      "containers": {
        "vxlan-processor": {
          "interfaces": [
            {
              "name": "eth0",
              "network": "external-traffic", 
              "ip": {"address": "172.20.100.10", "mask": 24}
            }
          ],
          "vxlan_tunnel": {
            "src": "172.20.100.10",
            "dst": "172.20.100.1", 
            "vni": 100,
            "decap_next": "l2"
          }
        }
      },
      "traffic_config": {
        "vxlan_port": 4789,
        "vxlan_vni": 100,
        "inner_src_ip": "10.10.10.5",
        "inner_dst_ip": "10.10.10.10"
      }
    }
  }
}
```

### Dynamic Configuration Loading

The system automatically:
- Extracts container IPs from interface configurations
- Uses network gateways for traffic generation source IPs  
- Configures VXLAN tunnels from container specifications
- Sets up NAT44 mappings from security processor config
- Configures TAP interfaces from destination container settings

## Project Structure

```
vpp_chain/
├── README.md                       # This comprehensive documentation
├── config.json                    # **Master configuration** (all topology data)
├── CLAUDE.md                      # Claude Code guidance documentation
├── validation.sh                  # Comprehensive validation script
├── quick-start.sh                 # Quick setup script
├── src/
│   ├── main.py                    # **Primary CLI interface**
│   ├── utils/                     # Core Python modules
│   │   ├── config_manager.py     # **Config-driven management**
│   │   ├── container_manager.py  # Docker container lifecycle
│   │   ├── network_manager.py    # Network setup and testing
│   │   ├── traffic_generator.py  # **Config-driven traffic generation**
│   │   └── logger.py             # Logging and output formatting
│   ├── containers/               # VPP container configurations
│   │   ├── vxlan-config.sh       # VXLAN decapsulation config
│   │   ├── security-config.sh    # Consolidated security processing
│   │   ├── destination-config.sh # TAP interface and capture
│   │   ├── Dockerfile.vxlan      # VXLAN processor container
│   │   ├── Dockerfile.security   # Security processor container
│   │   └── Dockerfile.destination # Destination container
│   └── configs/
│       ├── startup.conf          # VPP startup configuration (no-pci)
│       └── start-vpp.sh          # VPP initialization script
├── tests/                        # Python unit tests
│   ├── test_integration.py       # End-to-end integration tests
│   └── test_container_manager.py # Container management tests
├── scripts/
│   └── testing/
│       ├── quick_traffic_check.sh # Quick traffic verification
│       └── verify_traffic_flow.py # Comprehensive traffic analysis
└── docs/
    ├── architecture.md           # Detailed architecture documentation
    ├── testing_guide.md          # Testing procedures and guidelines
    ├── troubleshooting.md        # Common issues and solutions
    └── manual_test_guide.md      # Manual testing procedures
```

## Troubleshooting

### Common Issues and Solutions

#### VM Management Connectivity Loss

**Problem**: VM loses management connectivity when running VPP chain
**Root Cause**: Docker networks using conflicting IP ranges (192.168.x.x)
**✅ Solution**: Project now uses isolated 172.20.x.x ranges that don't conflict with VM management

```bash
# Verify no conflicts
ip route show | grep -E "(default|10\.168\.)"
# Should show your management network (e.g., 10.168.0.x) is unaffected

# Confirm Docker networks are isolated
docker network ls
docker network inspect external-traffic | jq '.[0].IPAM.Config'
```

#### VPP Interface Stealing

**Problem**: VPP takes over host network interfaces
**Root Cause**: Missing `no-pci` configuration
**✅ Solution**: Project includes `dpdk { no-pci }` in all VPP startup configs

```bash
# Verify no-pci configuration
docker exec vxlan-processor cat /vpp-common/startup.conf | grep -A3 "dpdk"
# Should show: "no-pci"

# Check host interfaces remain intact
ip addr show ens160  # or your management interface
```

#### Packet Processing Verification

**Problem**: "Low success rate" in traffic tests
**Explanation**: VPP processes packets at high speed, bypassing Linux network stack

**✅ Verification Methods**:

```bash
# 1. Check interface statistics (most reliable)
docker exec vxlan-processor vppctl show interface
# Look for: rx packets, tx packets on vxlan_tunnel0

# 2. Check end-to-end packet flow
for container in vxlan-processor security-processor destination; do
  echo "=== $container ==="
  docker exec $container vppctl show interface | grep -E "(rx packets|tx packets)"
done

# 3. Verify specific processing stages
docker exec vxlan-processor vppctl show vxlan tunnel          # VXLAN decap
docker exec security-processor vppctl show nat44 sessions     # NAT44 
docker exec security-processor vppctl show ipsec sa           # IPsec
docker exec destination vppctl show interface tap0            # Final delivery
```

#### Configuration Issues

**Problem**: Containers fail to start or VPP misconfiguration
**Solution**: Use force rebuild after config changes

```bash
# Always rebuild after config.json changes
sudo python3 src/main.py cleanup
sudo python3 src/main.py setup --force

# Verify configuration loading
python3 -c "
from src.utils.config_manager import ConfigManager
config = ConfigManager()
print('Networks:', [n['name'] for n in config.get_networks()])
print('Containers:', list(config.get_containers().keys()))
"
```

### Performance Tuning

#### System Optimization

```bash
# Increase network buffer sizes
echo 'net.core.rmem_default = 262144' | sudo tee -a /etc/sysctl.conf
echo 'net.core.rmem_max = 16777216' | sudo tee -a /etc/sysctl.conf  
echo 'net.core.wmem_default = 262144' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

#### VPP Performance Tuning

```bash
# Set interfaces to interrupt mode (lower CPU usage)
for container in vxlan-processor security-processor destination; do
  docker exec $container vppctl set interface rx-mode host-eth0 interrupt
  docker exec $container vppctl set interface rx-mode host-eth1 interrupt 2>/dev/null || true
done

# Enable larger MTU for jumbo frames (if needed)
docker exec vxlan-processor vppctl set interface mtu packet 9000 host-eth0
```

## Advanced Usage

### Custom Network Topologies

Modify `config.json` to create custom topologies:

```json
{
  "modes": {
    "custom": {
      "networks": [
        {
          "name": "custom-network",
          "subnet": "10.100.0.0/24",
          "gateway": "10.100.0.1"
        }
      ],
      "containers": {
        "vxlan-processor": {
          "interfaces": [
            {
              "network": "custom-network",
              "ip": {"address": "10.100.0.10", "mask": 24}
            }
          ]
        }
      }
    }
  }
}
```

### Traffic Generation Customization

Modify traffic parameters in `config.json`:

```json
{
  "traffic_config": {
    "vxlan_vni": 200,           # Custom VNI
    "packet_count": 100,        # More packets
    "packet_size": 1500,        # Different size
    "inner_src_ip": "192.168.1.10",  # Custom inner IPs
    "inner_dst_ip": "192.168.1.20"
  }
}
```

### Integration Testing

```bash
# Run comprehensive validation
sudo ./validation.sh

# Custom test scenarios
sudo python3 -c "
from src.utils.traffic_generator import TrafficGenerator
from src.utils.config_manager import ConfigManager

config = ConfigManager()
traffic = TrafficGenerator(config)
# Custom testing logic here
"
```

## Architecture Benefits

### Consolidated Design Advantages

- **50% Resource Reduction**: 3 containers vs traditional 6-container setups
- **Simplified Networking**: Fewer inter-container hops and networks
- **Easier Debugging**: Logical separation of concerns
- **Better Performance**: Reduced network overhead between processing stages
- **Configuration Flexibility**: Single config.json controls entire topology

### Security Features

- **Network Isolation**: Each processing stage in separate Docker networks
- **No Host Interface Interference**: VPP `no-pci` prevents interface stealing
- **IPsec Encryption**: AES-GCM-128 ESP encryption between security and destination
- **NAT44 Translation**: Address translation for network segmentation
- **Packet Fragmentation**: Handles large packets with MTU enforcement

## Use Cases

### Production Scenarios

1. **Multi-Cloud Connectivity**
   - VXLAN tunneling between different cloud providers
   - Secure NAT and IPsec processing for inter-cloud traffic

2. **Network Function Virtualization (NFV)**
   - Chained network services in containerized environments
   - High-performance packet processing for telecom applications

3. **Microservices Security**
   - Service mesh data plane with encryption and NAT
   - Container-to-container secure communication

4. **Edge Computing**
   - Network processing at edge locations
   - Low-latency packet transformation and forwarding

5. **Enterprise Gateway**
   - Combined VXLAN, NAT, and IPsec processing
   - Secure connectivity for hybrid cloud environments

## Contributing

1. **Fork** the repository
2. **Create** feature branch: `git checkout -b feature/amazing-feature`
3. **Make** changes and ensure all tests pass: `sudo python3 src/main.py test`
4. **Update** documentation if needed
5. **Commit** changes: `git commit -m "feat: add amazing feature"`
6. **Push** and create pull request

### Development Guidelines

- All network topology must be config-driven
- No hardcoded IP addresses or interface names
- Comprehensive testing required for new features
- Documentation updates for user-facing changes

## License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**Built for Cloud-Native, High-Performance Network Processing**

*Demonstrating production-ready VPP containerization with complete configuration flexibility and comprehensive testing capabilities.*