# VPP Multi-Container Chain Testing Guide

## Overview

This guide provides comprehensive testing procedures for the VPP Multi-Container Chain system. The testing framework validates container connectivity, VPP functionality, traffic processing, and end-to-end packet flow through the six-container pipeline.

## System Requirements

### Prerequisites

**Software Requirements:**
- Docker Engine 20.10 or later
- Python 3.8 or later
- Root privileges for container and network management
- Minimum 4GB available RAM for VPP containers

**Network Requirements:**
- Available IP address space: 172.20.0.0/16
- No conflicting Docker networks in the 172.20.x.x range
- Sufficient Docker bridge capacity for six networks

**System Setup:**
```bash
# Initial environment setup
sudo python3 src/main.py setup

# Verify setup completion
sudo python3 src/main.py status
```

## Testing Framework

### Test Categories

The testing system provides three distinct test categories:

**1. Connectivity Testing**
- Container health verification
- VPP process responsiveness
- Inter-container network reachability
- Interface configuration validation

**2. Traffic Testing**
- End-to-end packet flow validation
- VXLAN encapsulation/decapsulation
- NAT44 translation verification
- IPsec encryption functionality
- IP fragmentation processing
- Jumbo packet handling (up to 8KB)

**3. Full Test Suite**
- Combines connectivity and traffic testing
- Comprehensive system validation
- Performance metrics collection

### Test Execution Commands

#### Complete System Validation
```bash
# Full test suite (recommended)
sudo python3 src/main.py test

# Equivalent explicit command
sudo python3 src/main.py test --type full
```

#### Connectivity-Only Testing
```bash
# Quick connectivity verification
sudo python3 src/main.py test --type connectivity
```

#### Traffic-Only Testing
```bash
# Data plane validation
sudo python3 src/main.py test --type traffic
```

## Deployment Mode Testing

### Available Deployment Modes

The system supports multiple deployment configurations defined in `config.json`:

**GCP Mode (Default)**:
- Network range: 172.20.x.x
- Six dedicated inter-container networks
- Optimized for Google Cloud Platform deployment
- Default packet size: 8000 bytes (jumbo packets)

**AWS Mode**:
- Network range: 10.0.x.x with 172.31.x.x underlay
- Simplified network topology
- AWS VPC-compatible addressing
- Default packet size: 1200 bytes

### Mode-Specific Testing

#### GCP Mode Testing (Default)
```bash
# Setup and test GCP mode (explicit)
sudo python3 src/main.py setup --mode gcp
sudo python3 src/main.py test --mode gcp
```

#### AWS Mode Testing
```bash
# Setup and test AWS mode
sudo python3 src/main.py setup --mode aws
sudo python3 src/main.py test --mode aws

# Connectivity test in AWS mode
sudo python3 src/main.py test --type connectivity --mode aws
```

#### Mode Validation
```bash
# Verify current mode configuration
python3 src/main.py status --mode <mode>

# Compare mode configurations
sudo python3 src/main.py debug chain-ingress "show interface addr" --mode gcp
sudo python3 src/main.py debug chain-ingress "show interface addr" --mode aws
```

## Advanced Testing Procedures

### System Status and Monitoring

#### Container Health Verification
```bash
# Overall system status
sudo python3 src/main.py status

# Container-specific status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# VPP process verification
sudo python3 src/main.py debug chain-ingress "show version"
```

#### Real-time Monitoring
```bash
# Monitor chain for 2 minutes
python3 src/main.py monitor --duration 120

# Extended monitoring (10 minutes)
python3 src/main.py monitor --duration 600
```

### Container-Level Debugging

#### VPP Command Execution
```bash
# NAT44 session inspection
sudo python3 src/main.py debug chain-nat "show nat44 sessions"

# Interface statistics
sudo python3 src/main.py debug chain-vxlan "show interface"

# IPsec tunnel status
sudo python3 src/main.py debug chain-ipsec "show ipsec sa"

# Fragmentation statistics
sudo python3 src/main.py debug chain-fragment "show ip fib"
```

#### Network Configuration Verification
```bash
# IP address assignments
sudo python3 src/main.py debug chain-ingress "show interface addr"

# Routing table inspection
sudo python3 src/main.py debug chain-nat "show ip fib"

# Bridge domain status (VXLAN)
sudo python3 src/main.py debug chain-vxlan "show bridge-domain"
```

### Comprehensive Validation

#### Full System Validation Script
```bash
# Execute comprehensive validation
sudo ./comprehensive-validation.sh

# View validation results
cat /tmp/validation_results.log
```

#### Traffic Analysis
```bash
# Enable packet tracing (per container)
sudo python3 src/main.py debug chain-ingress "trace add af-packet-input 10"
sudo python3 src/main.py debug chain-vxlan "trace add af-packet-input 10"

# View packet traces
sudo python3 src/main.py debug chain-ingress "show trace"
```

### Performance Testing

#### Jumbo Packet Testing
```bash
# Configure jumbo packet traffic
# Edit config.json: "packet_size": 8000

# Run traffic test with large packets
sudo python3 src/main.py test --type traffic

# Verify fragmentation
sudo python3 src/main.py debug chain-fragment "show ip fib"
```

#### Throughput Analysis
```bash
# Monitor interface statistics during testing
while true; do
  sudo python3 src/main.py debug chain-ingress "show interface" | grep -A5 "host-eth"
  sleep 5
done
```

### Test Result Interpretation

#### Expected Success Indicators

**Connectivity Tests:**
- All containers report "running" status
- VPP processes respond to CLI commands
- Interface addresses correctly assigned
- Inter-container ping succeeds (where applicable)

**Traffic Tests:**
- Packet transmission confirmed at ingress
- Traffic visible at each processing stage
- Fragmentation occurs for packets > 1400 bytes
- Final packet delivery to GCP container

**Performance Metrics:**
- Interface TX/RX counters increment during traffic
- No packet drops reported in VPP statistics
- CPU utilization remains reasonable (<80%)
- Memory usage stable during testing

### Troubleshooting Test Failures

#### Common Issues and Solutions

**Container Startup Failures:**
```bash
# Check Docker logs
docker logs chain-<container-name>

# Verify VPP configuration
sudo python3 src/main.py debug chain-<container> "show logging"
```

**Network Connectivity Issues:**
```bash
# Verify Docker networks
docker network ls | grep chain

# Check IP assignments
sudo python3 src/main.py debug chain-ingress "show interface addr"
```

**Traffic Flow Problems:**
```bash
# Enable detailed tracing
sudo python3 src/main.py debug chain-<container> "trace add af-packet-input 50"

# Check NAT translations
sudo python3 src/main.py debug chain-nat "show nat44 sessions"
```

### Environment Cleanup

#### Complete System Cleanup
```bash
# Stop and remove all containers and networks
sudo python3 src/main.py cleanup

# Verify cleanup completion
docker ps -a | grep chain
docker network ls | grep chain
```

#### Selective Cleanup
```bash
# Remove specific containers only
docker stop chain-ingress chain-vxlan
docker rm chain-ingress chain-vxlan

# Force cleanup if containers are unresponsive
docker rm -f $(docker ps -aq --filter "name=chain-")
```

## Testing Best Practices

### Pre-Test Verification
1. Ensure sufficient system resources (RAM, CPU)
2. Verify no conflicting Docker networks exist
3. Confirm VPP version compatibility (v24.10-release)
4. Check Docker Engine status and version

### During Testing
1. Monitor system resource utilization
2. Observe container logs for errors
3. Verify packet flow at each processing stage
4. Document any unexpected behavior

### Post-Test Analysis
1. Review VPP statistics and counters
2. Analyze packet traces for processing correctness
3. Validate performance metrics against expectations
4. Clean up test environment completely

This comprehensive testing guide ensures thorough validation of the VPP Multi-Container Chain system across all supported deployment modes and operational scenarios.