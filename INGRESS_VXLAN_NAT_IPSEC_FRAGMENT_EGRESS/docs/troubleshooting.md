# VPP Multi-Container Chain Troubleshooting Guide

## Common Issues and Solutions

### 1. Container Startup Issues

#### Issue: Containers fail to start
```bash
Error: Container chain-vxlan exited with code 1
```

**Diagnosis:**
```bash
# Check container logs
docker logs chain-vxlan

# Check VPP logs
tail -f /tmp/vpp-logs/vpp.log
```

**Solutions:**
- **VPP startup failure**: Check that startup.conf is valid
- **Permission issues**: Ensure running with sudo/root privileges
- **Memory issues**: Verify system has 8GB+ RAM available
- **Port conflicts**: Check if ports 5002 are available

#### Issue: VPP fails to initialize
```
ERROR: VPP failed to start properly
```

**Solutions:**
- Check VPP configuration: `docker exec <container> cat /etc/vpp/startup.conf`
- Verify no-pci setting is present in DPDK section
- Check system hugepages: `cat /proc/meminfo | grep Huge`
- Verify VPP binary: `docker exec <container> which vpp`

### 2. Network Connectivity Issues

#### Issue: Inter-container communication fails
```bash
sudo python3 src/main.py test --type connectivity
❌ Connectivity test failed
```

**Diagnosis:**
```bash
# Check Docker networks
docker network ls
docker network inspect ingress_vxlan_nat_ipsec_fragment_egress_underlay

# Check container IP assignments
docker inspect <container-name> | grep IPAddress
```

**Solutions:**
- Verify docker-compose.yml network configuration
- Check container IP addresses match configuration scripts
- Ensure Docker bridge networking is enabled
- Restart Docker daemon if networks are corrupted

#### Issue: VPP interfaces not created
```bash
vppctl show interface
# No interfaces shown
```

**Solutions:**
- Check that configuration scripts are executable
- Verify VPP is responsive: `vppctl show version`
- Review interface creation commands in config scripts
- Check for kernel module conflicts

### 3. VPP Configuration Issues

#### Issue: VXLAN decapsulation not working
```bash
vppctl show vxlan tunnel
# No tunnels shown
```

**Diagnosis:**
```bash
# Check VXLAN configuration
sudo python3 src/main.py debug chain-vxlan "show vxlan tunnel"
sudo python3 src/main.py debug chain-vxlan "show bridge-domain"
```

**Solutions:**
- Verify VXLAN plugin is loaded: `vppctl show plugins`
- Check tunnel endpoints match container IPs
- Ensure VNI 100 is configured correctly
- Verify bridge domain configuration

#### Issue: NAT translation not working
```bash
vppctl show nat44 sessions
# No sessions shown
```

**Solutions:**
- Enable NAT44 plugin: `vppctl nat44 plugin enable`
- Check static mappings: `vppctl show nat44 static mappings`
- Verify interface NAT configuration: `vppctl show nat44 interfaces`
- Check NAT address pool: `vppctl show nat44 addresses`

#### Issue: IPsec encryption failing
```bash
vppctl show ipsec sa
# SAs not established
```

**Solutions:**
- Check IPsec plugin: `vppctl show plugins | grep ipsec`
- Verify SA configuration: `vppctl show ipsec sa verbose`
- Check tunnel protection: `vppctl show ipsec tunnel`
- Ensure crypto keys are correctly configured

### 4. Traffic Generation Issues

#### Issue: No traffic reaching destination
```bash
sudo python3 src/main.py test --type traffic
❌ Traffic test failed
```

**Diagnosis:**
```bash
# Check packet traces
sudo python3 src/main.py debug chain-ingress "show trace"
sudo python3 src/main.py debug chain-vxlan "show trace"

# Check interface statistics
sudo python3 src/main.py debug chain-gcp "show interface"
```

**Solutions:**
- Verify traffic generator is sending to correct interface
- Check packet format matches VXLAN expectations
- Ensure all containers are fully configured before testing
- Review routing tables: `vppctl show ip fib`

### 5. Performance Issues

#### Issue: Low packet throughput
**Diagnosis:**
```bash
# Check CPU usage
htop

# Check VPP performance
vppctl show runtime
vppctl show hardware
```

**Solutions:**
- Increase VPP memory allocation in startup.conf
- Optimize buffer configuration
- Check for CPU bottlenecks
- Review packet processing pipeline efficiency

### 6. Docker-related Issues

#### Issue: Docker Compose failures
```bash
ERROR: Version in "./docker-compose.yml" is unsupported
```

**Solutions:**
- Update Docker Compose to version 1.25+
- Check docker-compose.yml syntax
- Verify Docker daemon is running
- Update Docker to latest stable version

#### Issue: Volume mount issues
```bash
Error: No such file or directory: /vpp-config
```

**Solutions:**
- Ensure configuration files exist before starting containers
- Check file permissions on mounted volumes
- Verify absolute paths in volume mounts
- Create required directories: `mkdir -p /tmp/vpp-logs /tmp/packet-captures`

### 7. System Requirements Issues

#### Issue: Insufficient memory
```bash
Cannot allocate memory
```

**Solutions:**
- Ensure system has 8GB+ RAM
- Close unnecessary applications
- Adjust VPP memory settings in startup.conf
- Consider using swap if necessary (not recommended for production)

## Debugging Commands Reference

### Container Management
```bash
# View all container status
docker ps -a

# Check container logs
docker logs <container-name>

# Access container shell
docker exec -it <container-name> bash

# Restart specific container
docker restart <container-name>
```

### VPP Debugging
```bash
# VPP CLI access
docker exec -it <container-name> vppctl

# Common VPP debug commands
vppctl show version
vppctl show interface
vppctl show interface addr
vppctl show ip fib
vppctl show trace
vppctl clear trace
vppctl trace add af-packet-input 10
```

### Network Debugging
```bash
# Check Docker networks
docker network ls
docker network inspect <network-name>

# Test container connectivity
docker exec <container> ping <ip>

# Check routing
docker exec <container> ip route show
```

### Log Analysis
```bash
# VPP logs
tail -f /tmp/vpp-logs/vpp.log

# Container logs
docker logs -f <container-name>

# System logs
journalctl -u docker
```

## Getting Help

1. **Check logs first**: Always start with container and VPP logs
2. **Verify configuration**: Ensure all config files match expected format
3. **Test incrementally**: Use debug commands to test each container stage
4. **Check system resources**: Monitor CPU, memory, and network usage
5. **Consult documentation**: Review architecture.md for expected behavior