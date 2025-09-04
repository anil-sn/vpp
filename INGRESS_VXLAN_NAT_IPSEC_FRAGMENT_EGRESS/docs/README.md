# VPP Multi-Container Chain Documentation

## Overview

This directory contains comprehensive documentation for the VPP Multi-Container Chain project.

## Contents

- [`architecture.md`](architecture.md) - Detailed system architecture and design
- [`troubleshooting.md`](troubleshooting.md) - Common issues and solutions  
- [`performance.md`](performance.md) - Performance tuning and optimization
- [`development.md`](development.md) - Development guidelines and contribution process

## Quick Start

For immediate setup and testing, see the main [README.md](../README.md) in the project root.

## Architecture Summary

```
INGRESS → VXLAN → NAT44 → IPSEC → FRAGMENT → GCP
   ↓        ↓       ↓        ↓        ↓       ↓
192.168   10.1.1  10.1.2   10.1.3   10.1.4  192.168
.10.2     .2      .2       .2       .2      .10.3
```

## Support

For issues and questions:
1. Check [troubleshooting.md](troubleshooting.md)
2. Review container logs: `docker logs <container-name>`
3. Use debug commands: `sudo python3 src/main.py debug <container> "<command>"`