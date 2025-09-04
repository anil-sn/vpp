# VPP Multi-Container Chain Documentation

## Overview

This directory contains comprehensive documentation for the VPP Multi-Container Chain project, a high-performance network processing pipeline that demonstrates VXLAN decapsulation, NAT translation, IPsec encryption, and packet fragmentation across distributed Docker containers using Vector Packet Processing (VPP).

## Contents

- [`architecture.md`](architecture.md) - Detailed system architecture, network topology, and component specifications
- [`testing_guide.md`](testing_guide.md) - Comprehensive testing procedures and validation methods  
- [`troubleshooting.md`](troubleshooting.md) - Common issues, diagnostic procedures, and solutions

## System Architecture

The VPP Multi-Container Chain implements a six-container pipeline processing network packets through the following stages:

```
INGRESS → VXLAN → NAT44 → IPSEC → FRAGMENT → GCP
```

### Network Topology
- External Ingress Network: 172.20.0.0/24
- Inter-container Networks: 172.20.1.0/24 through 172.20.5.0/24
- Container Chain: Six specialized VPP instances for packet processing

### Key Features
- VXLAN tunnel decapsulation (VNI 100)
- NAT44 address translation (10.10.10.10 to 172.20.3.10)
- IPsec ESP encryption with AES-GCM-128
- IP fragmentation with configurable MTU (1400 bytes)
- Jumbo packet support (up to 8KB tested)

## Quick Start

For immediate setup and testing:
1. Review system requirements in the main [README.md](../README.md)
2. Execute: `sudo python3 src/main.py setup`
3. Run tests: `sudo python3 src/main.py test`
4. Monitor: `python3 src/main.py status`

## Documentation Standards

This documentation follows professional technical writing standards:
- Clear, objective language without decorative elements
- Comprehensive coverage of system components and operations
- Structured format for easy navigation and reference
- Practical examples and configuration details

## Support and Diagnostics

For technical issues and system diagnosis:
1. Consult the troubleshooting guide: [troubleshooting.md](troubleshooting.md)
2. Review container logs: `docker logs <container-name>`
3. Access VPP CLI: `docker exec <container> vppctl <command>`
4. Debug specific containers: `sudo python3 src/main.py debug <container> "<command>"`
5. Run comprehensive validation: `sudo ./comprehensive-validation.sh`