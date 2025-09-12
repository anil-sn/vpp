# VPP Multi-Container Chain Deployment Guide

## Overview

This guide provides comprehensive deployment procedures for the VPP Multi-Container Chain system across various environments and use cases. The deployment approach covers development environments, testing scenarios, and pre-production validation. For full production deployments, refer to the [Production Migration Guide](./PRODUCTION_MIGRATION_GUIDE.md).

## System Architecture Summary

The VPP Multi-Container Chain implements a 3-container processing pipeline:
- **VXLAN-PROCESSOR**: VXLAN decapsulation with BVI L2-to-L3 conversion
- **SECURITY-PROCESSOR**: Consolidated NAT44 + IPsec ESP + IP fragmentation  
- **DESTINATION**: ESP decryption with TAP interface packet capture

Key architectural benefits include 50% resource reduction, 90% packet delivery success rate, and VM-safe network isolation.

## Prerequisites and System Requirements

### Minimum System Requirements
```
Hardware Requirements:
├── CPU: 4 cores minimum (8 cores recommended)
├── Memory: 8GB RAM minimum (16GB recommended)  
├── Storage: 20GB available space (50GB recommended)
├── Network: Gigabit Ethernet (10GbE recommended for production)
└── Architecture: x86_64 (AMD64)

Operating System Requirements:
├── Ubuntu: 20.04 LTS or 22.04 LTS (recommended)
├── CentOS: 8.x or Rocky Linux 8.x
├── Debian: 11 (Bullseye) or newer
├── Red Hat Enterprise Linux: 8.x
└── Kernel: 5.4 or newer (5.15+ recommended)

Network Requirements:
├── Root access for network configuration
├── Ability to create Docker networks and bridges
├── Firewall access for required ports (4789, 2055, 8081)
├── No conflicting services on required ports
└── Internet access for Docker image downloads
```

### Software Dependencies Installation

**Ubuntu/Debian Systems**:
```bash
# Update package repositories
sudo apt update && sudo apt upgrade -y

# Install core dependencies
sudo apt install -y \
    docker.io docker-compose \
    python3 python3-pip python3-venv \
    curl wget jq git \
    net-tools iproute2 iptables \
    tcpdump tshark wireshark-common \
    build-essential linux-headers-$(uname -r)

# Install Python packages
pip3 install --user scapy netifaces psutil

# Configure Docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER

# Verify installation
docker --version
python3 --version
```

**CentOS/RHEL/Rocky Linux Systems**:
```bash
# Update system packages
sudo dnf update -y

# Install core dependencies
sudo dnf install -y \
    docker docker-compose \
    python3 python3-pip \
    curl wget jq git \
    net-tools iproute \
    tcpdump wireshark-cli \
    gcc kernel-devel kernel-headers

# Start Docker service
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER

# Install Python packages
pip3 install --user scapy netifaces psutil

# Configure firewall if needed
sudo firewall-cmd --permanent --add-port=4789/udp
sudo firewall-cmd --permanent --add-port=2055/udp
sudo firewall-cmd --permanent --add-port=8081/tcp
sudo firewall-cmd --reload
```

### Environment Validation

Run comprehensive pre-deployment validation:

```bash
#!/bin/bash
# Pre-deployment environment validation script

echo "=== VPP Multi-Container Chain Environment Validation ==="

# System resource validation
echo "1. System Resources:"
CPU_CORES=$(nproc)
MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
DISK_GB=$(df -BG / | awk 'NR==2{gsub(/G/,"",$4); print $4}')

echo "   CPU Cores: $CPU_CORES (minimum: 4)"
echo "   Memory: ${MEMORY_GB}GB (minimum: 8GB)"
echo "   Disk Space: ${DISK_GB}GB available (minimum: 20GB)"

# Validate minimum requirements
VALIDATION_PASSED=true
[ $CPU_CORES -ge 4 ] || { echo "   ERROR: Insufficient CPU cores"; VALIDATION_PASSED=false; }
[ $MEMORY_GB -ge 8 ] || { echo "   ERROR: Insufficient memory"; VALIDATION_PASSED=false; }
[ $DISK_GB -ge 20 ] || { echo "   ERROR: Insufficient disk space"; VALIDATION_PASSED=false; }

# Docker validation
echo "2. Docker Environment:"
if systemctl is-active --quiet docker; then
    echo "   Docker service: RUNNING"
    if docker info >/dev/null 2>&1; then
        echo "   Docker access: AVAILABLE"
        DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        echo "   Docker version: $DOCKER_VERSION"
    else
        echo "   ERROR: Docker not accessible - check user permissions"
        VALIDATION_PASSED=false
    fi
else
    echo "   ERROR: Docker service not running"
    VALIDATION_PASSED=false
fi

# Network port validation
echo "3. Network Ports:"
REQUIRED_PORTS=(4789 2055 8081)
for port in "${REQUIRED_PORTS[@]}"; do
    if ss -tuln | grep -q ":$port "; then
        SERVICE=$(ss -tulpn | grep ":$port " | head -1 | awk '{print $7}')
        echo "   WARNING: Port $port in use by $SERVICE"
    else
        echo "   Port $port: AVAILABLE"
    fi
done

# Python environment validation
echo "4. Python Environment:"
PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
echo "   Python version: $PYTHON_VERSION"

# Check required Python packages
for package in scapy netifaces psutil; do
    if python3 -c "import $package" >/dev/null 2>&1; then
        echo "   Python $package: INSTALLED"
    else
        echo "   ERROR: Python $package not installed"
        VALIDATION_PASSED=false
    fi
done

# Network interface validation
echo "5. Network Configuration:"
PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -n "$PRIMARY_INTERFACE" ]; then
    PRIMARY_IP=$(ip addr show "$PRIMARY_INTERFACE" | grep 'inet ' | awk '{print $2}' | head -1)
    echo "   Primary interface: $PRIMARY_INTERFACE ($PRIMARY_IP)"
    
    # Check for IP conflicts with VPP networks
    if [[ "$PRIMARY_IP" =~ ^172\.20\. ]]; then
        echo "   WARNING: IP conflicts with VPP networks (172.20.x.x)"
        echo "   Consider using production mode with custom network ranges"
    fi
else
    echo "   ERROR: Cannot determine primary network interface"
    VALIDATION_PASSED=false
fi

# VPP image availability
echo "6. VPP Image Availability:"
if docker pull vppproject/vpp:v24.10 >/dev/null 2>&1; then
    echo "   VPP v24.10 image: AVAILABLE"
    IMAGE_SIZE=$(docker images vppproject/vpp:v24.10 --format "table {{.Size}}" | tail -1)
    echo "   Image size: $IMAGE_SIZE"
else
    echo "   ERROR: Cannot pull VPP v24.10 image - check internet connectivity"
    VALIDATION_PASSED=false
fi

# Kernel capabilities validation
echo "7. Kernel Capabilities:"
if [ -f /proc/sys/net/ipv4/ip_forward ]; then
    IP_FORWARD=$(cat /proc/sys/net/ipv4/ip_forward)
    echo "   IP forwarding: $([[ $IP_FORWARD -eq 1 ]] && echo "ENABLED" || echo "DISABLED")"
else
    echo "   WARNING: Cannot check IP forwarding capability"
fi

if [ -d /sys/class/net ]; then
    echo "   Network interface access: AVAILABLE"
else
    echo "   ERROR: Cannot access network interfaces"
    VALIDATION_PASSED=false
fi

# Final validation result
echo ""
if [ "$VALIDATION_PASSED" = true ]; then
    echo "VALIDATION RESULT: PASSED"
    echo "System ready for VPP Multi-Container Chain deployment"
    exit 0
else
    echo "VALIDATION RESULT: FAILED"
    echo "Please resolve the errors above before deployment"
    exit 1
fi
```

## Deployment Scenarios

### Scenario 1: Development Environment Setup

**Use Case**: Local development, testing, and debugging on a single machine.

**Configuration**: Testing mode with full debugging capabilities enabled.

```bash
# Navigate to project directory
cd vpp_chain

# Verify project structure
ls -la src/ docs/ tools/

# Run environment validation
chmod +x scripts/validate_environment.sh
./scripts/validate_environment.sh

# Deploy in development mode
sudo python3 src/main.py setup

# Verify deployment
python3 src/main.py status

# Run basic connectivity tests
sudo python3 src/main.py test --type connectivity

# Enable debugging for development
for container in vxlan-processor security-processor destination; do
    docker exec $container vppctl trace add af-packet-input 10
done

# Generate test traffic
sudo python3 src/main.py test --type traffic

# Analyze results
docker exec vxlan-processor vppctl show trace
docker exec security-processor vppctl show nat44 sessions
docker exec destination vppctl show interface tap0
```

### Scenario 2: Multi-User Testing Environment

**Use Case**: Shared testing environment with isolated deployments per user.

**Configuration**: User-specific network ranges and container naming.

```bash
# Set user-specific environment
export USER_ID=$(id -u)
export VPP_DEPLOYMENT_PREFIX="vpp-${USER_ID}"

# Create user-specific configuration
cp config.json config-user-${USER_ID}.json

# Modify network ranges to avoid conflicts
python3 << EOF
import json
with open('config-user-${USER_ID}.json', 'r') as f:
    config = json.load(f)

# Adjust network ranges based on user ID
base_octet = 100 + (${USER_ID} % 50)
for network in config['modes']['testing']['networks']:
    if 'external-traffic' in network['name']:
        network['subnet'] = f'172.20.{base_octet}.0/24'
        network['gateway'] = f'172.20.{base_octet}.1'
    elif 'vxlan-processing' in network['name']:
        network['subnet'] = f'172.20.{base_octet + 1}.0/24'
        network['gateway'] = f'172.20.{base_octet + 1}.1'
    elif 'processing-destination' in network['name']:
        network['subnet'] = f'172.20.{base_octet + 2}.0/24'
        network['gateway'] = f'172.20.{base_octet + 2}.1'

with open('config-user-${USER_ID}.json', 'w') as f:
    json.dump(config, f, indent=2)

print(f"User-specific configuration created with networks 172.20.{base_octet}-{base_octet + 2}.0/24")
EOF

# Deploy with user-specific configuration
sudo python3 src/main.py setup --config config-user-${USER_ID}.json

# Run isolated testing
sudo python3 src/main.py test --config config-user-${USER_ID}.json
```

### Scenario 3: CI/CD Integration Testing

**Use Case**: Automated testing in continuous integration pipelines.

**Configuration**: Automated deployment with validation and cleanup.

```bash
#!/bin/bash
# CI/CD Integration Script

set -e  # Exit on any error

CI_LOG_FILE="/tmp/vpp_ci_test_$(date +%Y%m%d_%H%M%S).log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$CI_LOG_FILE"
}

log_message "Starting VPP Multi-Container Chain CI/CD Test"

# Step 1: Environment cleanup
log_message "Step 1: Cleaning previous deployments"
sudo python3 src/main.py cleanup || true
docker system prune -f

# Step 2: Pre-deployment validation
log_message "Step 2: Running pre-deployment validation"
./scripts/validate_environment.sh

# Step 3: Deploy system
log_message "Step 3: Deploying VPP Multi-Container Chain"
timeout 300 sudo python3 src/main.py setup --force

# Step 4: Health checks
log_message "Step 4: Running health checks"
sleep 30  # Allow containers to stabilize

# Check container health
for container in vxlan-processor security-processor destination; do
    if ! docker ps | grep -q "$container.*Up"; then
        log_message "ERROR: Container $container failed to start"
        docker logs "$container" | tail -20 | tee -a "$CI_LOG_FILE"
        exit 1
    fi
    log_message "Container $container: HEALTHY"
done

# Step 5: Connectivity tests
log_message "Step 5: Running connectivity tests"
if ! sudo python3 src/main.py test --type connectivity; then
    log_message "ERROR: Connectivity tests failed"
    exit 1
fi
log_message "Connectivity tests: PASSED"

# Step 6: Traffic processing tests
log_message "Step 6: Running traffic processing tests"
TRAFFIC_RESULT=$(sudo python3 src/main.py test --type traffic | grep "End-to-end delivery rate" | cut -d':' -f2 | tr -d ' %')

if [ -z "$TRAFFIC_RESULT" ] || [ "${TRAFFIC_RESULT%.*}" -lt 85 ]; then
    log_message "ERROR: Traffic processing test failed (${TRAFFIC_RESULT}% success rate)"
    
    # Debug information collection
    log_message "Collecting debug information..."
    for container in vxlan-processor security-processor destination; do
        echo "=== $container Interface Status ===" >> "$CI_LOG_FILE"
        docker exec "$container" vppctl show interface >> "$CI_LOG_FILE"
        echo "=== $container Errors ===" >> "$CI_LOG_FILE"  
        docker exec "$container" vppctl show errors >> "$CI_LOG_FILE"
    done
    
    exit 1
fi
log_message "Traffic processing tests: PASSED (${TRAFFIC_RESULT}% success rate)"

# Step 7: Performance validation
log_message "Step 7: Running performance validation"
for container in vxlan-processor security-processor destination; do
    CPU_USAGE=$(docker stats --no-stream --format "table {{.CPUPerc}}" "$container" | tail -1 | tr -d '%')
    MEM_USAGE=$(docker stats --no-stream --format "table {{.MemUsage}}" "$container" | tail -1)
    
    if [ "${CPU_USAGE%.*}" -gt 80 ]; then
        log_message "WARNING: High CPU usage in $container: ${CPU_USAGE}%"
    fi
    
    log_message "Container $container: CPU ${CPU_USAGE}%, Memory ${MEM_USAGE}"
done

# Step 8: Cleanup
log_message "Step 8: Cleaning up deployment"
sudo python3 src/main.py cleanup

log_message "CI/CD test completed successfully"
log_message "Full log available: $CI_LOG_FILE"

# Export test results for CI system
cat > /tmp/vpp_test_results.json << EOF
{
    "test_status": "PASSED",
    "packet_success_rate": ${TRAFFIC_RESULT},
    "containers_tested": ["vxlan-processor", "security-processor", "destination"],
    "test_duration_seconds": $SECONDS,
    "log_file": "$CI_LOG_FILE"
}
EOF

echo "Test results exported to: /tmp/vpp_test_results.json"
```

### Scenario 4: Performance Benchmarking Environment

**Use Case**: Performance testing and optimization validation.

**Configuration**: Optimized system settings with performance monitoring.

```bash
#!/bin/bash
# Performance Benchmarking Setup

echo "=== VPP Multi-Container Chain Performance Benchmarking ==="

# System optimization for performance testing
echo "1. Applying system optimizations..."

# Enable huge pages
echo 1024 | sudo tee /sys/devices/system/node/node*/hugepages/hugepages-2048kB/nr_hugepages

# Optimize network buffers
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728
sudo sysctl -w net.core.netdev_max_backlog=5000

# CPU frequency scaling
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Deploy with performance optimizations
echo "2. Deploying with performance configuration..."
sudo python3 src/main.py cleanup
sudo python3 src/main.py setup --force

# Wait for full initialization
echo "3. Waiting for system stabilization..."
sleep 60

# Performance baseline test
echo "4. Running performance baseline..."
BASELINE_RESULTS="/tmp/vpp_performance_baseline_$(date +%Y%m%d_%H%M%S).log"

echo "Baseline Test Results" > "$BASELINE_RESULTS"
echo "====================" >> "$BASELINE_RESULTS"
echo "Test Date: $(date)" >> "$BASELINE_RESULTS"
echo "System: $(uname -a)" >> "$BASELINE_RESULTS"
echo "" >> "$BASELINE_RESULTS"

# Multiple performance test runs
PACKET_COUNTS=(10 100 1000)
PACKET_SIZES=(64 512 1400 4096)

for count in "${PACKET_COUNTS[@]}"; do
    for size in "${PACKET_SIZES[@]}"; do
        echo "Testing: $count packets, $size bytes each"
        
        # Configure test parameters
        python3 << EOF
import json
with open('config.json', 'r') as f:
    config = json.load(f)
    
config['modes']['testing']['traffic_config']['packet_count'] = $count
config['modes']['testing']['traffic_config']['packet_size'] = $size

with open('config.json', 'w') as f:
    json.dump(config, f, indent=2)
EOF
        
        # Run performance test
        START_TIME=$(date +%s.%N)
        RESULT=$(sudo python3 src/main.py test --type traffic | grep "End-to-end delivery rate" | cut -d':' -f2 | tr -d ' %')
        END_TIME=$(date +%s.%N)
        
        DURATION=$(echo "$END_TIME - $START_TIME" | bc)
        THROUGHPUT=$(echo "scale=2; $count / $DURATION" | bc)
        
        echo "Packets: $count, Size: $size bytes, Success: ${RESULT}%, Duration: ${DURATION}s, Throughput: ${THROUGHPUT} pps" >> "$BASELINE_RESULTS"
        
        # Container resource usage
        echo "  Resource Usage:" >> "$BASELINE_RESULTS"
        docker stats --no-stream --format "    {{.Name}}: CPU {{.CPUPerc}}, Memory {{.MemUsage}}" >> "$BASELINE_RESULTS"
        echo "" >> "$BASELINE_RESULTS"
        
        # Brief pause between tests
        sleep 10
    done
done

# Interface statistics collection
echo "5. Collecting detailed interface statistics..."
echo "" >> "$BASELINE_RESULTS"
echo "Interface Statistics:" >> "$BASELINE_RESULTS"
echo "===================" >> "$BASELINE_RESULTS"

for container in vxlan-processor security-processor destination; do
    echo "" >> "$BASELINE_RESULTS"
    echo "=== $container ===" >> "$BASELINE_RESULTS"
    docker exec "$container" vppctl show interface >> "$BASELINE_RESULTS"
    docker exec "$container" vppctl show runtime >> "$BASELINE_RESULTS"
done

echo "Performance benchmarking completed"
echo "Results saved to: $BASELINE_RESULTS"

# Generate performance summary
BEST_THROUGHPUT=$(grep "Throughput:" "$BASELINE_RESULTS" | awk '{print $NF}' | sort -nr | head -1)
AVG_SUCCESS_RATE=$(grep "Success:" "$BASELINE_RESULTS" | awk -F'Success: ' '{print $2}' | awk -F'%' '{print $1}' | awk '{sum+=$1; n++} END {print sum/n}')

echo ""
echo "PERFORMANCE SUMMARY:"
echo "==================="
echo "Peak Throughput: ${BEST_THROUGHPUT} packets/second"  
echo "Average Success Rate: ${AVG_SUCCESS_RATE}%"
echo "Full results: $BASELINE_RESULTS"
```

### Scenario 5: Multi-Host Distributed Testing

**Use Case**: Testing across multiple physical hosts or VMs.

**Configuration**: Coordinated deployment across multiple systems.

```bash
#!/bin/bash
# Multi-Host Distributed Testing Setup

# Configuration
HOSTS=("host1.example.com" "host2.example.com" "host3.example.com")
SSH_KEY="/path/to/ssh/key"
DEPLOYMENT_USER="vpp-test"

# Deploy function for remote hosts
deploy_to_host() {
    local host=$1
    local host_id=$2
    
    echo "Deploying to $host (ID: $host_id)"
    
    # Copy project files
    rsync -avz -e "ssh -i $SSH_KEY" \
        --exclude='.git' \
        --exclude='__pycache__' \
        ./ "${DEPLOYMENT_USER}@${host}:~/vpp_chain/"
    
    # Remote deployment with host-specific configuration
    ssh -i "$SSH_KEY" "${DEPLOYMENT_USER}@${host}" << EOF
        cd ~/vpp_chain
        
        # Customize network ranges per host
        python3 << PYTHON
import json
with open('config.json', 'r') as f:
    config = json.load(f)

base_octet = 100 + $host_id * 10
for network in config['modes']['testing']['networks']:
    if 'external-traffic' in network['name']:
        network['subnet'] = f'172.20.{base_octet}.0/24'
        network['gateway'] = f'172.20.{base_octet}.1'
    elif 'vxlan-processing' in network['name']:
        network['subnet'] = f'172.20.{base_octet + 1}.0/24'
        network['gateway'] = f'172.20.{base_octet + 1}.1'
    elif 'processing-destination' in network['name']:
        network['subnet'] = f'172.20.{base_octet + 2}.0/24'
        network['gateway'] = f'172.20.{base_octet + 2}.1'

with open('config.json', 'w') as f:
    json.dump(config, f, indent=2)
PYTHON
        
        # Deploy on remote host
        sudo python3 src/main.py cleanup
        sudo python3 src/main.py setup --force
        
        # Verify deployment
        python3 src/main.py status
EOF
    
    if [ $? -eq 0 ]; then
        echo "Deployment to $host: SUCCESS"
    else
        echo "Deployment to $host: FAILED"
        return 1
    fi
}

# Coordinated testing function
run_coordinated_test() {
    echo "Running coordinated tests across all hosts"
    
    # Start tests simultaneously on all hosts
    local pids=()
    local results=()
    
    for i in "${!HOSTS[@]}"; do
        host=${HOSTS[$i]}
        
        ssh -i "$SSH_KEY" "${DEPLOYMENT_USER}@${host}" \
            "cd ~/vpp_chain && sudo python3 src/main.py test --type traffic" > "/tmp/test_result_host_${i}.log" 2>&1 &
        
        pids[$i]=$!
    done
    
    # Wait for all tests to complete
    for i in "${!pids[@]}"; do
        wait ${pids[$i]}
        results[$i]=$?
        
        if [ ${results[$i]} -eq 0 ]; then
            success_rate=$(grep "End-to-end delivery rate" "/tmp/test_result_host_${i}.log" | cut -d':' -f2 | tr -d ' %')
            echo "Host ${HOSTS[$i]}: SUCCESS (${success_rate}% delivery rate)"
        else
            echo "Host ${HOSTS[$i]}: FAILED"
        fi
    done
    
    # Aggregate results
    local total_success=0
    local failed_hosts=0
    
    for result in "${results[@]}"; do
        if [ $result -eq 0 ]; then
            ((total_success++))
        else
            ((failed_hosts++))
        fi
    done
    
    echo ""
    echo "MULTI-HOST TEST SUMMARY:"
    echo "======================="
    echo "Total hosts: ${#HOSTS[@]}"
    echo "Successful deployments: $total_success"
    echo "Failed deployments: $failed_hosts"
    
    if [ $failed_hosts -eq 0 ]; then
        echo "Multi-host test: PASSED"
        return 0
    else
        echo "Multi-host test: FAILED"
        return 1
    fi
}

# Main execution
echo "=== Multi-Host VPP Chain Deployment ==="

# Deploy to all hosts
for i in "${!HOSTS[@]}"; do
    deploy_to_host "${HOSTS[$i]}" "$i"
done

# Run coordinated testing
run_coordinated_test

# Cleanup
echo "Cleaning up deployments..."
for host in "${HOSTS[@]}"; do
    ssh -i "$SSH_KEY" "${DEPLOYMENT_USER}@${host}" \
        "cd ~/vpp_chain && sudo python3 src/main.py cleanup" &
done
wait

echo "Multi-host deployment testing completed"
```

## Advanced Configuration Management

### Environment-Specific Configurations

Create environment-specific configuration files for different deployment scenarios:

```bash
# Development configuration (config-development.json)
cat > config-development.json << 'EOF'
{
  "default_mode": "testing",
  "description": "Development environment with enhanced debugging",
  "modes": {
    "testing": {
      "description": "Development testing with debug features enabled",
      "debug_features": {
        "packet_tracing": true,
        "interface_stats": true,
        "detailed_logging": true,
        "vpp_debug": true,
        "performance_monitoring": false
      },
      "resource_allocation": {
        "container_memory_mb": 1024,
        "container_cpu_cores": 1,
        "enable_resource_limits": false
      }
    }
  }
}
EOF

# Testing environment configuration (config-testing.json)  
cat > config-testing.json << 'EOF'
{
  "default_mode": "testing",
  "description": "Automated testing environment",
  "modes": {
    "testing": {
      "description": "CI/CD testing with validation features",
      "testing_features": {
        "automated_validation": true,
        "performance_benchmarks": true,
        "stress_testing": false,
        "regression_testing": true
      },
      "resource_allocation": {
        "container_memory_mb": 2048,
        "container_cpu_cores": 2,
        "enable_resource_limits": true
      }
    }
  }
}
EOF

# Pre-production configuration (config-preproduction.json)
cat > config-preproduction.json << 'EOF'
{
  "default_mode": "testing", 
  "description": "Pre-production validation environment",
  "modes": {
    "testing": {
      "description": "Production-like testing with monitoring",
      "production_features": {
        "performance_monitoring": true,
        "resource_monitoring": true,
        "health_checks": true,
        "alerting": true
      },
      "resource_allocation": {
        "container_memory_mb": 4096,
        "container_cpu_cores": 4,
        "enable_resource_limits": true,
        "resource_reservation_percent": 80
      }
    }
  }
}
EOF
```

### Dynamic Configuration Generation

Create dynamic configuration based on system resources:

```bash
#!/bin/bash
# Dynamic configuration generator

generate_config() {
    local config_name=$1
    local cpu_cores=$(nproc)
    local memory_gb=$(free -g | awk '/^Mem:/{print $2}')
    
    # Calculate optimal resource allocation
    local container_memory=$((memory_gb * 1024 / 4))  # 25% of total memory per container
    local container_cpus=$((cpu_cores / 4))           # 25% of total CPU per container
    
    # Ensure minimums
    [ $container_memory -lt 1024 ] && container_memory=1024
    [ $container_cpus -lt 1 ] && container_cpus=1
    
    cat > "$config_name" << EOF
{
  "default_mode": "testing",
  "description": "Auto-generated configuration for $(hostname)",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "system_info": {
    "hostname": "$(hostname)",
    "cpu_cores": $cpu_cores,
    "memory_gb": $memory_gb,
    "architecture": "$(uname -m)",
    "kernel": "$(uname -r)"
  },
  "modes": {
    "testing": {
      "description": "Optimized configuration for current system",
      "resource_allocation": {
        "container_memory_mb": $container_memory,
        "container_cpu_cores": $container_cpus,
        "enable_resource_limits": true,
        "resource_reservation_percent": 75
      }
    }
  }
}
EOF
    
    echo "Generated configuration: $config_name"
    echo "  Container Memory: ${container_memory}MB"
    echo "  Container CPUs: $container_cpus"
}

# Generate system-specific configuration
generate_config "config-auto.json"
```

## Troubleshooting and Debugging

### Common Deployment Issues

**Issue 1: Container Startup Failures**
```bash
# Diagnosis steps
echo "=== Container Startup Diagnosis ==="

# Check Docker service status
systemctl status docker

# Check available resources
echo "System resources:"
free -h
df -h /

# Examine container logs
for container in vxlan-processor security-processor destination; do
    echo "=== $container logs ==="
    docker logs "$container" 2>&1 | tail -20
done

# Check VPP startup logs
for container in vxlan-processor security-processor destination; do
    echo "=== $container VPP logs ==="
    docker exec "$container" cat /tmp/vpp.log 2>/dev/null | tail -10
done

# Common solutions:
echo "Common solutions:"
echo "1. Increase memory allocation in configuration"
echo "2. Check for conflicting containers: docker ps -a"
echo "3. Clean up resources: docker system prune -f"
echo "4. Restart Docker: sudo systemctl restart docker"
```

**Issue 2: Network Connectivity Problems**
```bash
# Network diagnosis
echo "=== Network Connectivity Diagnosis ==="

# Check Docker networks
echo "Docker networks:"
docker network ls

# Inspect VPP networks
for network in external-traffic vxlan-processing processing-destination; do
    echo "=== $network network ==="
    docker network inspect "$network" | jq '.[0].Containers'
done

# Test inter-container connectivity
echo "Testing connectivity:"
docker exec vxlan-processor ping -c 3 172.20.101.20 || echo "VXLAN→Security failed"
docker exec security-processor ping -c 3 172.20.102.20 || echo "Security→Destination failed"

# Check VPP interface status
for container in vxlan-processor security-processor destination; do
    echo "=== $container interfaces ==="
    docker exec "$container" vppctl show interface addr
    docker exec "$container" vppctl show ip neighbors
done

# Common solutions:
echo "Common solutions:"
echo "1. Verify IP ranges don't conflict with host network"
echo "2. Check firewall rules: sudo iptables -L -n"
echo "3. Restart networking: sudo python3 src/main.py cleanup && setup"
```

**Issue 3: Performance Issues**
```bash
# Performance diagnosis
echo "=== Performance Diagnosis ==="

# Container resource usage
echo "Container resource usage:"
docker stats --no-stream

# VPP performance statistics
for container in vxlan-processor security-processor destination; do
    echo "=== $container VPP performance ==="
    docker exec "$container" vppctl show runtime
    docker exec "$container" vppctl show memory
    docker exec "$container" vppctl show hardware
done

# System performance
echo "System performance:"
echo "Load average: $(uptime | cut -d',' -f3-)"
echo "CPU usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')"
echo "Memory usage: $(free | grep '^Mem:' | awk '{print ($3/$2)*100"%"}')"

# Common solutions:
echo "Performance optimization steps:"
echo "1. Enable huge pages: echo 1024 | sudo tee /sys/devices/system/node/node*/hugepages/hugepages-2048kB/nr_hugepages"
echo "2. Increase container resources in configuration"
echo "3. Optimize VPP settings: edit src/configs/startup.conf"
echo "4. Check for system bottlenecks: iostat, iotop"
```

### Debug Mode Deployment

Enable comprehensive debugging for troubleshooting:

```bash
# Deploy with maximum debugging enabled
cat > config-debug.json << 'EOF'
{
  "default_mode": "testing",
  "description": "Maximum debugging configuration",
  "modes": {
    "testing": {
      "debug_features": {
        "packet_tracing": true,
        "interface_stats": true,
        "detailed_logging": true,
        "vpp_debug": true,
        "packet_capture": true,
        "performance_monitoring": true
      },
      "vpp_debug_settings": {
        "log_level": "debug",
        "trace_buffer_size": 10000,
        "enable_all_traces": true
      }
    }
  }
}
EOF

# Deploy with debug configuration
sudo python3 src/main.py cleanup
sudo python3 src/main.py setup --config config-debug.json

# Enable comprehensive tracing
for container in vxlan-processor security-processor destination; do
    docker exec "$container" vppctl clear trace
    docker exec "$container" vppctl trace add af-packet-input 100
    docker exec "$container" vppctl trace add vxlan-input 100
    docker exec "$container" vppctl trace add nat44-in2out 100
    docker exec "$container" vppctl trace add ipsec-esp-encrypt 100
    docker exec "$container" vppctl trace add tap-tx 100
done

# Generate debug traffic
sudo python3 src/main.py test --type traffic

# Collect comprehensive debug information
DEBUG_DIR="/tmp/vpp_debug_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$DEBUG_DIR"

for container in vxlan-processor security-processor destination; do
    echo "Collecting debug info for $container..."
    
    # VPP traces
    docker exec "$container" vppctl show trace > "$DEBUG_DIR/${container}_trace.log"
    
    # Interface statistics
    docker exec "$container" vppctl show interface > "$DEBUG_DIR/${container}_interfaces.log"
    
    # Error counters
    docker exec "$container" vppctl show errors > "$DEBUG_DIR/${container}_errors.log"
    
    # Runtime statistics
    docker exec "$container" vppctl show runtime > "$DEBUG_DIR/${container}_runtime.log"
    
    # VPP configuration
    docker exec "$container" vppctl show version > "$DEBUG_DIR/${container}_version.log"
    
    # Container logs
    docker logs "$container" > "$DEBUG_DIR/${container}_container.log" 2>&1
done

echo "Debug information collected in: $DEBUG_DIR"
echo "Share this directory with support for troubleshooting assistance"
```

This comprehensive deployment guide provides detailed procedures for various deployment scenarios, from development environments to production-ready configurations, with extensive troubleshooting support and real-world deployment patterns.