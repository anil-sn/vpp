# VPP Multi-Container Chain Deployment Guide

## Overview

This guide covers standard deployment procedures for the VPP Multi-Container Chain system in development and testing environments. For production deployments, see the [Production Migration Guide](./PRODUCTION_MIGRATION_GUIDE.md).

## Prerequisites

### System Requirements
- **Operating System**: Linux (Ubuntu 20.04+ recommended)
- **Docker**: Version 20.10 or higher with Docker Compose
- **Python**: Version 3.8 or higher
- **Memory**: Minimum 8GB RAM (16GB+ recommended)
- **CPU**: Multi-core processor (4+ cores recommended)
- **Network**: Root access required for network configuration

### Required Permissions
- **Root Access**: Most operations require sudo privileges
- **Docker Access**: User must be in docker group or use sudo
- **Network Configuration**: Ability to create and modify network interfaces

### Installation Dependencies
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y docker.io docker-compose python3 python3-pip

# Install Python dependencies
pip3 install scapy netifaces

# Add user to docker group (logout/login required)
sudo usermod -aG docker $USER

# Verify Docker installation
docker --version
docker-compose --version
```

## Quick Start Deployment

### 1. Standard Setup
```bash
# Clone and navigate to repository
git clone <repository-url>
cd vpp_chain

# Setup complete environment (testing configuration)
sudo python3 src/main.py setup

# Verify deployment
python3 src/main.py status

# Run comprehensive tests
sudo python3 src/main.py test
```

### 2. Force Rebuild Setup
```bash
# Clean existing environment
sudo python3 src/main.py cleanup

# Force rebuild and setup
sudo python3 src/main.py setup --force

# Run validation script
sudo ./quick-start.sh
```

## Configuration Modes

### Testing Mode (Default)
**Configuration File**: `config.json`
- **Network Addressing**: 172.20.x.x (VM-safe)
- **Container Count**: 3 (vxlan-processor, security-processor, destination)
- **Features**: Full packet processing pipeline with debugging enabled
- **Use Case**: Development, testing, validation

```bash
# Use testing configuration (default)
sudo python3 src/main.py setup
```

### Production Mode
**Configuration File**: `production.json`
- **Network Integration**: AWS Traffic Mirroring → GCP FDI
- **Enhanced Features**: Monitoring, alerting, source IP preservation
- **Use Case**: Production AWS→GCP pipeline deployment

```bash
# Use production configuration
sudo python3 src/main.py setup --config production.json
```

## Deployment Steps

### Step 1: Environment Preparation
```bash
# Verify system requirements
python3 -c "import sys; print(f'Python version: {sys.version}')"
docker --version

# Check available resources
free -h
df -h
nproc

# Verify network configuration
ip addr show
```

### Step 2: Configuration Validation
```bash
# Validate configuration syntax
python3 -c "import json; json.load(open('config.json'))"

# Check for configuration conflicts
python3 src/main.py status

# Review network settings
grep -E "subnet|gateway" config.json
```

### Step 3: Container Deployment
```bash
# Clean any existing deployment
sudo python3 src/main.py cleanup

# Deploy containers with proper ordering
sudo python3 src/main.py setup --force

# Monitor deployment progress
python3 src/main.py status
```

### Step 4: Connectivity Validation
```bash
# Test inter-container connectivity
sudo python3 src/main.py test --type connectivity

# Verify VPP container interfaces
for container in vxlan-processor security-processor destination; do
    echo "=== $container Interface Status ==="
    docker exec $container vppctl show interface
done
```

### Step 5: Traffic Processing Validation
```bash
# Run traffic processing tests
sudo python3 src/main.py test --type traffic

# Enable packet tracing for detailed analysis
for container in vxlan-processor security-processor destination; do
    docker exec $container vppctl clear trace
    docker exec $container vppctl trace add af-packet-input 10
done

# Generate test traffic
sudo python3 src/main.py test --type traffic

# Analyze packet traces
docker exec vxlan-processor vppctl show trace
docker exec security-processor vppctl show trace  
docker exec destination vppctl show trace
```

## Network Configuration

### Network Topology Setup
The deployment creates three isolated Docker networks:

1. **external-traffic** (172.20.100.0/24)
   - Gateway: 172.20.100.1
   - MTU: 9000
   - Purpose: VXLAN traffic ingress

2. **vxlan-processing** (172.20.101.0/24)
   - Gateway: 172.20.101.1
   - MTU: 9000
   - Purpose: VXLAN→Security communication

3. **processing-destination** (172.20.102.0/24)
   - Gateway: 172.20.102.1
   - MTU: 1500
   - Purpose: Security→Destination communication

### Container Interface Assignment
```bash
# VXLAN-PROCESSOR interfaces
# eth0: 172.20.100.10/24 (external-traffic)
# eth1: 172.20.101.10/24 (vxlan-processing)

# SECURITY-PROCESSOR interfaces  
# eth0: 172.20.101.20/24 (vxlan-processing)
# eth1: 172.20.102.10/24 (processing-destination)

# DESTINATION interfaces
# eth0: 172.20.102.20/24 (processing-destination)
# tap0: 10.0.3.1/24 (TAP interface)
```

## Testing and Validation

### Connectivity Tests
```bash
# Test basic connectivity
sudo python3 src/main.py test --type connectivity

# Manual connectivity verification
docker exec vxlan-processor ping -c 3 172.20.101.20
docker exec security-processor ping -c 3 172.20.102.20
```

### Traffic Processing Tests
```bash
# Complete traffic processing validation
sudo python3 src/main.py test --type traffic

# Check packet statistics
for container in vxlan-processor security-processor destination; do
    echo "=== $container Statistics ==="
    docker exec $container vppctl show interface
    docker exec $container vppctl show errors
done
```

### Debug and Monitoring
```bash
# Enable comprehensive debugging
sudo python3 src/main.py debug vxlan-processor "show vxlan tunnel"
sudo python3 src/main.py debug security-processor "show nat44 sessions"
sudo python3 src/main.py debug security-processor "show ipsec sa"
sudo python3 src/main.py debug destination "show interface"

# Monitor VPP performance
for container in vxlan-processor security-processor destination; do
    echo "=== $container Performance ==="
    docker exec $container vppctl show runtime
    docker exec $container vppctl show memory
done
```

## Common Deployment Issues

### Container Startup Issues
```bash
# Check container logs
docker logs vxlan-processor
docker logs security-processor  
docker logs destination

# Verify VPP startup
docker exec <container> cat /tmp/vpp.log
```

### Network Connectivity Issues
```bash
# Verify Docker networks
docker network ls
docker network inspect external-traffic

# Check interface configuration
docker exec <container> ip addr show
docker exec <container> vppctl show interface addr
```

### Configuration Issues
```bash
# Validate JSON syntax
python3 -m json.tool config.json

# Check VPP configuration files
ls -la src/containers/*.sh
```

## Cleanup and Reset

### Complete Environment Reset
```bash
# Stop and remove all containers
sudo python3 src/main.py cleanup

# Remove Docker networks (optional)
docker network prune

# Clean up temporary files
sudo rm -rf /tmp/*vpp*
```

### Selective Cleanup
```bash
# Stop specific container
docker stop <container-name>

# Remove specific network
docker network rm <network-name>

# Clear VPP traces
docker exec <container> vppctl clear trace
```

## Performance Tuning

### System Optimization
```bash
# Enable huge pages
echo 1024 | sudo tee /sys/devices/system/node/node*/hugepages/hugepages-2048kB/nr_hugepages

# Set CPU isolation (optional)
# Add isolcpus=2-7 to kernel boot parameters

# Optimize network buffers
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728
```

### VPP Memory Tuning
Adjust memory settings in VPP startup configuration:
```bash
# Edit src/configs/startup.conf
main-core 1
corelist-workers 2-3
buffers-per-numa 16384
```

## Monitoring and Maintenance

### Regular Health Checks
```bash
# Container health verification
python3 src/main.py status

# Interface statistics monitoring
for container in vxlan-processor security-processor destination; do
    docker exec $container vppctl show interface
done

# Error monitoring
for container in vxlan-processor security-processor destination; do
    docker exec $container vppctl show errors
done
```

### Log Management
```bash
# VPP logs
docker exec <container> tail -f /tmp/vpp.log

# Container logs
docker logs -f <container-name>

# System logs
journalctl -u docker
```

This deployment guide provides a comprehensive approach to setting up and maintaining the VPP Multi-Container Chain system in various environments.