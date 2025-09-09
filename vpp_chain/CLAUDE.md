# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Core Architecture

This is a **VPP Multi-Container Chain** system that implements a high-performance network processing pipeline using Vector Packet Processing (VPP) v24.10-release distributed across three specialized Docker containers. The system processes packets through VXLAN decapsulation, NAT44 translation, IPsec encryption, and IP fragmentation in a consolidated, efficient architecture.

### Container Processing Pipeline
```
VXLAN-PROCESSOR → SECURITY-PROCESSOR → DESTINATION
```

Each container runs a dedicated VPP instance with specific network functions:
- **vxlan-processor**: VXLAN decapsulation, VNI 100 (172.20.0.10 → 172.20.1.10)
- **security-processor**: NAT44 translation + IPsec ESP AES-GCM-128 encryption + IP fragmentation (172.20.1.20 → 172.20.2.10)
- **destination**: Final destination endpoint with TAP interface and packet capture (172.20.2.20)

### Network Topology
- **external-traffic** (172.20.0.0/24): External VXLAN traffic ingress
- **vxlan-processing** (172.20.1.0/24): VXLAN to Security Processor communication
- **processing-destination** (172.20.2.0/24): Security Processor to Destination communication

## Essential Commands

**Root access is required for most operations.**

### Setup and Management
```bash
# Setup the multi-container chain
sudo python3 src/main.py setup

# Setup with forced rebuild
sudo python3 src/main.py setup --force

# Show current chain status
python3 src/main.py status

# Monitor chain for specified duration
python3 src/main.py monitor --duration 120

# Clean up environment
sudo python3 src/main.py cleanup
```

### Testing
```bash
# Run full test suite (connectivity + traffic)
sudo python3 src/main.py test

# Test only connectivity between containers
sudo python3 src/main.py test --type connectivity

# Test only traffic generation and processing
sudo python3 src/main.py test --type traffic

# Comprehensive validation script
sudo ./validation.sh
```

### Debugging VPP Containers
```bash
# Debug specific container with VPP commands
sudo python3 src/main.py debug <container> "<vpp-command>"

# Common debug commands:
sudo python3 src/main.py debug vxlan-processor "show vxlan tunnel"
sudo python3 src/main.py debug security-processor "show nat44 sessions"
sudo python3 src/main.py debug security-processor "show ipsec sa"
sudo python3 src/main.py debug security-processor "show ipip tunnel"
sudo python3 src/main.py debug destination "show interface"
sudo python3 src/main.py debug destination "show trace"

# Direct VPP CLI access
docker exec -it <container-name> vppctl
```

### Key File Locations

**Main Entry Point**: `src/main.py` - CLI interface for all operations

**Core Modules**:
- `src/utils/container_manager.py`: Docker container management with manual container start
- `src/utils/network_manager.py`: Network setup and connectivity testing  
- `src/utils/traffic_generator.py`: Traffic generation using Scapy
- `src/utils/config_manager.py`: Configuration management from `config.json`
- `src/utils/logger.py`: Logging and output formatting

**VPP Configuration Scripts**: (optimized for 3-container architecture)
- `src/containers/vxlan-config.sh` - VXLAN decapsulation with L2 bridging
- `src/containers/security-config.sh` - NAT44 + IPsec + Fragmentation processing
- `src/containers/destination-config.sh` - TAP interface with interrupt mode and packet capture

**Configuration**: `config.json` - Network topology and container specifications
**Documentation**: Consolidated into `README.md`, plus `docs/architecture.md`, `docs/testing_guide.md`, `docs/troubleshooting.md`

## Development Workflow

1. **Make Changes**: Modify configuration scripts in `src/containers/` or Python modules in `src/utils/`
2. **Test Locally**: Use `sudo python3 src/main.py setup` to rebuild and test
3. **Debug Issues**: Use debug commands and check VPP logs in containers
4. **Validate**: Run full test suite with `sudo python3 src/main.py test`
5. **Clean Up**: Use cleanup command when switching configurations

## Architecture Benefits

**Consolidated 3-Container Design**:
- 50% reduction in resource usage (from 6 to 3 containers)
- Simplified network topology and debugging
- Logical separation: Network Processing | Security Processing | Destination
- Maintained functionality with improved efficiency

## VPP Specifics

**VPP Version**: v24.10-release
**Memory**: 256MB main heap, 16384 buffers per NUMA
**Essential Plugins**: af_packet, vxlan, nat, ipsec, crypto_native
**Packet Size**: Default 2048 bytes, supports jumbo packets up to 8KB
**MTU**: Fragment container enforces 1400 byte MTU

**VPP CLI Socket**: `/run/vpp/cli.sock` in each container
**Log Location**: `/tmp/vpp.log` in each container

## Traffic Flow

Test traffic follows this optimized path:
1. VXLAN packet (VNI 100) sent to VXLAN-PROCESSOR (172.20.0.10:4789)
2. Inner packet: IP(10.10.10.5 → 10.10.10.10)/UDP(dport: 2055)
3. VXLAN decapsulation extracts inner packet and forwards to SECURITY-PROCESSOR
4. NAT44 translates 10.10.10.10 → 172.20.2.10
5. IPsec encrypts with AES-GCM-128 in IPIP tunnel (172.20.1.20 → 172.20.2.20)
6. IP fragmentation splits packets > 1400 bytes MTU
7. DESTINATION receives, decrypts, and captures final packets via TAP interface

## Configuration Management

The system uses `config.json` for deployment modes. Currently supports "gcp" mode with 172.20.x.x addressing. To add new deployment modes, extend the "modes" section in `config.json` and update the configuration scripts accordingly.