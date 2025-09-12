# VPP Multi-Container Chain Documentation

Welcome to the VPP Multi-Container Chain documentation. This directory contains comprehensive guides for understanding, deploying, and maintaining the VPP processing pipeline.

## Documentation Structure

### Core Documentation
- **[Architecture Overview](./architecture.md)** - System architecture and design principles
- **[Deployment Guide](./deployment.md)** - Standard deployment procedures and configuration
- **[Production Migration Guide](./PRODUCTION_MIGRATION_GUIDE.md)** - Production deployment with AWS→GCP integration

### Technical References  
- **[Configuration Reference](./configuration.md)** - Complete configuration options and examples
- **[VPP Configuration Guide](./vpp-configuration.md)** - VPP-specific settings and optimizations
- **[Testing Guide](./testing.md)** - Testing procedures and validation workflows

### Operations & Maintenance
- **[Troubleshooting Guide](./troubleshooting.md)** - Common issues and solutions
- **[Monitoring & Debugging](./monitoring.md)** - Performance monitoring and debugging techniques
- **[Maintenance Procedures](./maintenance.md)** - Routine maintenance and updates

## Quick Start

For immediate deployment, see:
1. **Development/Testing**: Follow the main [README.md](../README.md) quick start
2. **Production Deployment**: Start with [Production Migration Guide](./PRODUCTION_MIGRATION_GUIDE.md)

## Architecture Summary

The VPP Multi-Container Chain implements a high-performance network processing pipeline:

```
VXLAN-PROCESSOR → SECURITY-PROCESSOR → DESTINATION
     ↓                   ↓                 ↓
VXLAN Decap        NAT44 + IPsec      ESP Decrypt
  VNI 100          + Fragmentation    + TAP Capture
  BVI L2→L3                          Final Delivery
```

### Key Benefits
- **50% resource reduction** compared to traditional 6-container setups
- **90%+ packet delivery success** with BVI L2-to-L3 architecture
- **Production-ready** AWS Traffic Mirroring → GCP FDI integration
- **VM-safe networking** preserves host management connectivity

## Support & Contributing

- **Issues**: Report issues in the main repository
- **Configuration Help**: See [Configuration Reference](./configuration.md)
- **Production Deployment**: Follow [Production Migration Guide](./PRODUCTION_MIGRATION_GUIDE.md)