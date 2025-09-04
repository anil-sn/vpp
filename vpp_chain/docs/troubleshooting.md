# VPP Multi-Container Chain Troubleshooting Guide

## Overview

This troubleshooting guide provides systematic diagnostic procedures and solutions for common issues encountered in the VPP Multi-Container Chain system. The guide covers container startup problems, network connectivity issues, VPP configuration errors, and performance optimization.

## System Diagnostics

### Initial System Health Check

Before troubleshooting specific issues, perform a comprehensive system health assessment:

```bash
# Overall system status
sudo python3 src/main.py status

# Container health verification
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Created}}"

# Network infrastructure check
docker network ls | grep -E "(chain|fragment|gcp)"

# Resource utilization
free -h && df -h /tmp
```

## Container-Level Issues

### Container Startup Failures

#### Symptom: Containers Exit Immediately
```
Error: Container chain-vxlan exited with code 1
```

**Diagnostic Steps:**
```bash
# Check container exit logs
docker logs chain-vxlan --details

# Examine VPP startup logs
sudo python3 src/main.py debug chain-vxlan "show logging"

# Verify container image integrity
docker images | grep vpp-chain
```

**Common Causes and Solutions:**

**VPP Initialization Failure:**
- **Cause**: Invalid VPP startup configuration
- **Solution**: Verify startup.conf syntax and plugin availability
```bash
docker exec chain-vxlan cat /etc/vpp/startup.conf
sudo python3 src/main.py debug chain-vxlan "show plugins"
```

**Memory Allocation Issues:**
- **Cause**: Insufficient system memory or incorrect VPP heap configuration
- **Solution**: Verify system resources and adjust memory settings
```bash
# Check available memory
free -h
# Review VPP memory configuration
grep -E "(main-heap|buffers)" src/containers/*/startup.conf
```

**Permission and Capabilities:**
- **Cause**: Insufficient container privileges for VPP operations
- **Solution**: Ensure privileged mode and required capabilities
```bash
docker inspect chain-vxlan | grep -A5 '"Privileged"'
```

### VPP Process Issues

#### Symptom: VPP CLI Unresponsive
```
vppctl: cannot connect to VPP
```

**Diagnostic Approach:**
```bash
# Verify VPP process status
docker exec chain-vxlan ps aux | grep vpp

# Check VPP socket availability
docker exec chain-vxlan ls -la /run/vpp/

# Test VPP responsiveness
sudo python3 src/main.py debug chain-vxlan "show version"
```

**Resolution Steps:**
1. **Restart VPP process** within container
2. **Verify socket permissions** in /run/vpp/
3. **Check configuration conflicts** in startup.conf
4. **Monitor resource consumption** during startup

## Network Connectivity Problems

### Inter-Container Communication Failures

#### Symptom: Connectivity Tests Fail
```
Connectivity test failed: chain-ingress -> 172.20.1.20
```

**Network Infrastructure Diagnostics:**
```bash
# Verify Docker network configuration
docker network inspect external-ingress
docker network inspect ingress-vxlan

# Check container network assignments
docker inspect chain-ingress | grep -A10 '"Networks"'
docker inspect chain-vxlan | grep -A10 '"Networks"'

# Validate IP address assignments
sudo python3 src/main.py debug chain-ingress "show interface addr"
sudo python3 src/main.py debug chain-vxlan "show interface addr"
```

**Network Layer Solutions:**

**Docker Network Issues:**
- **Recreate Docker networks** if configuration is corrupted
- **Verify subnet conflicts** with existing networks
- **Check bridge network availability** on the system

**VPP Interface Problems:**
- **Validate interface creation** using correct VPP syntax
- **Verify interface state** (up/down) and IP assignment
- **Check routing table** configuration for inter-container traffic

### VPP Interface Configuration Errors

#### Symptom: Interfaces Not Created
```bash
vppctl show interface
# Returns: No interfaces found
```

**Interface Configuration Validation:**
```bash
# Check configuration script execution
sudo python3 src/main.py debug chain-vxlan "show interface"

# Verify host interface creation
sudo python3 src/main.py debug chain-vxlan "show hardware-interfaces"

# Review interface assignment
sudo python3 src/main.py debug chain-vxlan "show interface addr"
```

**Common Configuration Fixes:**

**Incorrect VPP Syntax:**
- **Issue**: Using deprecated or incorrect VPP commands
- **Solution**: Update to `create host-interface name ethX` syntax

**Interface State Management:**
- **Issue**: Interfaces created but not brought up
- **Solution**: Ensure `set interface state host-ethX up` commands

**IP Address Assignment:**
- **Issue**: Missing or incorrect IP address configuration
- **Solution**: Verify `set interface ip address host-ethX <ip>/<prefix>` commands

## VPP Function-Specific Issues

### VXLAN Processing Problems

#### Symptom: VXLAN Decapsulation Fails
```bash
vppctl show vxlan tunnel
# No tunnels configured
```

**VXLAN Diagnostic Protocol:**
```bash
# Check VXLAN plugin status
sudo python3 src/main.py debug chain-vxlan "show plugins | grep vxlan"

# Verify tunnel configuration
sudo python3 src/main.py debug chain-vxlan "show vxlan tunnel"

# Examine bridge domain setup
sudo python3 src/main.py debug chain-vxlan "show bridge-domain"

# Analyze packet flow
sudo python3 src/main.py debug chain-vxlan "trace add af-packet-input 10"
```

**VXLAN Configuration Solutions:**
- **Verify VNI 100 configuration** matches traffic expectations
- **Check UDP port 4789** availability and binding
- **Validate bridge domain** L2/L3 mode configuration
- **Ensure VXLAN plugin** is properly loaded

### NAT44 Translation Issues

#### Symptom: NAT Sessions Not Established
```bash
vppctl show nat44 sessions
# No active sessions
```

**NAT44 Troubleshooting Process:**
```bash
# Verify NAT44 plugin status
sudo python3 src/main.py debug chain-nat "show plugins | grep nat"

# Check static mapping configuration
sudo python3 src/main.py debug chain-nat "show nat44 static mappings"

# Review interface NAT assignment
sudo python3 src/main.py debug chain-nat "show nat44 interfaces"

# Examine address pool
sudo python3 src/main.py debug chain-nat "show nat44 addresses"
```

**NAT44 Resolution Strategies:**
- **Enable NAT44 plugin** if not active
- **Configure static mappings** for 10.10.10.10 → 172.20.3.10
- **Set interface NAT roles** (inside/outside)
- **Verify address pool** availability

### IPsec Encryption Failures

#### Symptom: IPsec SAs Not Established
```bash
vppctl show ipsec sa
# No security associations
```

**IPsec Diagnostic Methodology:**
```bash
# Check IPsec plugin availability
sudo python3 src/main.py debug chain-ipsec "show plugins | grep ipsec"

# Examine SA configuration
sudo python3 src/main.py debug chain-ipsec "show ipsec sa verbose"

# Review tunnel protection
sudo python3 src/main.py debug chain-ipsec "show ipsec tunnel"

# Check crypto engine
sudo python3 src/main.py debug chain-ipsec "show crypto engines"
```

**IPsec Resolution Approaches:**
- **Verify AES-GCM-128** algorithm support
- **Check security association** configuration
- **Validate tunnel endpoints** and routing
- **Ensure crypto plugin** availability

### IP Fragmentation Problems

#### Symptom: Large Packets Not Fragmented
```bash
# Packets > 1400 bytes not being fragmented
```

**Fragmentation Diagnostics:**
```bash
# Check MTU configuration
sudo python3 src/main.py debug chain-fragment "show interface" | grep -A2 "mtu"

# Verify fragmentation capability
sudo python3 src/main.py debug chain-fragment "show ip fib"

# Monitor fragmentation statistics
sudo python3 src/main.py debug chain-fragment "show node counters"
```

**Fragmentation Solutions:**
- **Set MTU to 1400 bytes** on output interface
- **Enable IP fragmentation** in VPP configuration
- **Verify jumbo packet handling** for packets > 1400 bytes
- **Check reassembly** at destination container

## Traffic Flow Issues

### End-to-End Connectivity Problems

#### Symptom: No Traffic Reaching Destination
```bash
sudo python3 src/main.py test --type traffic
# Traffic test failed: No packets received
```

**Traffic Flow Analysis:**
```bash
# Enable packet tracing across chain
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  sudo python3 src/main.py debug $container "trace add af-packet-input 20"
done

# Check interface statistics
for container in chain-ingress chain-vxlan chain-nat chain-ipsec chain-fragment chain-gcp; do
  echo "=== $container ===" 
  sudo python3 src/main.py debug $container "show interface"
done

# Review packet traces
sudo python3 src/main.py debug chain-ingress "show trace"
```

**Traffic Flow Resolution:**
- **Verify traffic generator** target configuration
- **Check packet format** compliance with VXLAN standards
- **Ensure routing tables** direct traffic appropriately
- **Monitor processing stages** for packet drops

### Performance Optimization

#### Symptom: Low Packet Throughput
**Performance Analysis Protocol:**
```bash
# System resource utilization
htop
iostat -x 1

# VPP performance metrics
sudo python3 src/main.py debug chain-vxlan "show runtime"
sudo python3 src/main.py debug chain-vxlan "show hardware-interfaces"

# Buffer and memory usage
sudo python3 src/main.py debug chain-vxlan "show memory"
sudo python3 src/main.py debug chain-vxlan "show buffers"
```

**Performance Optimization Strategies:**
- **Increase buffer allocation** in VPP startup configuration
- **Optimize memory settings** for packet processing workload
- **Monitor CPU utilization** across container instances
- **Review packet processing** pipeline efficiency

## System-Level Diagnostics

### Resource Exhaustion Issues

#### Memory and Storage Problems
```bash
# System memory analysis
free -h
cat /proc/meminfo | grep -E "(MemTotal|MemAvailable|MemFree)"

# Disk space verification
df -h /tmp
du -sh /tmp/vpp-logs/*

# Docker resource usage
docker system df
```

**Resource Management:**
- **Ensure 4GB+ available RAM** for VPP containers
- **Monitor /tmp directory** space for logs
- **Clean up old containers** and images regularly
- **Adjust VPP memory allocation** based on available resources

### Docker Infrastructure Issues

#### Docker Service Problems
```bash
# Docker daemon status
systemctl status docker

# Docker version compatibility
docker --version
docker-compose --version

# Network driver availability
docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
```

**Docker Infrastructure Solutions:**
- **Restart Docker service** if unresponsive
- **Update Docker** to compatible version (20.10+)
- **Verify bridge networking** capability
- **Check Docker storage driver** configuration

## Systematic Troubleshooting Workflow

### Step-by-Step Diagnostic Process

**1. Environment Verification**
```bash
# System requirements check
sudo python3 src/main.py status
docker --version
free -h
```

**2. Container Health Assessment**
```bash
# Container status verification
docker ps -a | grep chain
docker logs --tail=50 chain-<problematic-container>
```

**3. Network Connectivity Testing**
```bash
# Network layer validation
sudo python3 src/main.py test --type connectivity
docker network inspect external-ingress
```

**4. VPP Function Validation**
```bash
# VPP service verification
sudo python3 src/main.py debug chain-vxlan "show interface"
sudo python3 src/main.py debug chain-nat "show nat44 sessions"
```

**5. Traffic Flow Analysis**
```bash
# End-to-end traffic testing
sudo python3 src/main.py test --type traffic
# Packet trace analysis per container
```

**6. Performance Optimization**
```bash
# Resource utilization monitoring
python3 src/main.py monitor --duration 120
# VPP performance metrics collection
```

## Emergency Recovery Procedures

### Complete System Reset
```bash
# Full environment cleanup
sudo python3 src/main.py cleanup

# Force container removal
docker rm -f $(docker ps -aq --filter "name=chain-")

# Network cleanup
docker network prune -f

# Fresh environment setup
sudo python3 src/main.py setup

# Verification
sudo python3 src/main.py test
```

### Selective Container Recovery
```bash
# Restart specific problematic container
docker restart chain-<container-name>

# Reconfigure VPP in container
sudo python3 src/main.py debug chain-<container-name> "clear interfaces"
# Re-run configuration script
```

## Debugging Command Reference

### Essential VPP Commands
```bash
# Interface management
show interface
show interface addr
show hardware-interfaces
set interface state <interface> up/down

# Packet tracing
trace add af-packet-input <count>
show trace
clear trace

# Plugin management
show plugins
show version

# Statistics and counters
show node counters
show runtime
show memory
show buffers
```

### Container Management Commands
```bash
# Container inspection
docker ps -a
docker logs <container-name>
docker exec -it <container-name> bash

# Network diagnostics
docker network ls
docker network inspect <network-name>
docker port <container-name>
```

### System Monitoring Commands
```bash
# Resource monitoring
htop
iostat -x 1
netstat -tuln
ss -tuln

# Log analysis
tail -f /tmp/vpp-logs/*.log
journalctl -u docker -f
```

This comprehensive troubleshooting guide provides systematic diagnostic procedures and resolution strategies for all common issues in the VPP Multi-Container Chain system. Follow the step-by-step workflows to efficiently identify and resolve problems at any system level.