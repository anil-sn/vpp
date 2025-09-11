# VPP Production Migration Guide

## Traffic Analysis Summary

Based on your packet captures:
- **Port 8081**: 100 packets, ~86KB direct UDP traffic to 100.104.12.3
- **Port 31765**: 99 packets, ~124KB VXLAN traffic to 10.2.66.179
- **Packet sizes**: 1400-1500 bytes (bulk data transfer)
- **Sources**: Google IPs (216.239.1.x), Cloudflare (67.55.150.x), others

## Production Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│ TRAFFIC-INGRESS │───▶│ SECURITY-PROCESSOR│───▶│ANALYTICS-DESTINATION│
│ Port 8081/31765 │    │ NAT44 + IPsec    │    │ Monitoring + Logs   │
│ VXLAN Decap     │    │ AES-GCM-256      │    │ Prometheus/Grafana  │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
```

## Migration Steps

### Step 1: Pre-Production Setup
```bash
# Copy production configuration
cp config-production.json config.json

# Update VPP for production workloads  
sudo python3 src/main.py setup --force --mode production

# Verify containers
python3 src/main.py status
```

### Step 2: Configure Port Mirroring

**For Physical Switches (Cisco/Juniper):**
```bash
# Cisco IOS Example
configure terminal
monitor session 1 source interface GigabitEthernet0/1
monitor session 1 destination interface GigabitEthernet0/2
```

**For Linux Bridge/OVS:**
```bash
# Create mirror interfaces for your traffic
sudo ip link add vpp-mirror0 type veth peer name vpp-mirror0-peer
sudo ip link set vpp-mirror0 up
sudo ip link set vpp-mirror0-peer up

# Mirror traffic from your interface (replace ens6 with your interface)
sudo tc qdisc add dev ens6 handle ffff: ingress
sudo tc filter add dev ens6 parent ffff: protocol all u32 match u32 0 0 \
    action mirred egress mirror dev vpp-mirror0
```

### Step 3: Production Container Configuration

**High-Performance VPP Settings:**
```bash
# Enable CPU isolation
echo "isolcpus=2-7 nohz_full=2-7 rcu_nocbs=2-7" | sudo tee -a /boot/grub/grub.cfg

# Configure huge pages
echo 1024 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Optimize network interfaces
for iface in ens6 ens7; do
    sudo ethtool -C $iface rx 4096 tx 4096
    sudo ethtool -G $iface rx 4096 tx 4096
    sudo ethtool -K $iface gro on lro on tso on gso on
done
```

### Step 4: Production Traffic Processing

**Start VPP Chain with Production Config:**
```bash
# Clean setup for production
sudo python3 src/main.py cleanup
sudo python3 src/main.py setup --force

# Enable production monitoring
sudo python3 src/main.py debug traffic-ingress "set interface rx-mode host-eth0 polling"
sudo python3 src/main.py debug security-processor "set interface rx-mode host-eth0 polling"
```

### Step 5: Real Traffic Integration

**Configure Traffic Capture:**
```bash
# Enable packet capture on ingress
docker exec traffic-ingress vppctl packet-generator enable-stream pg0

# Configure VXLAN tunnel for your actual VNI
docker exec traffic-ingress vppctl create vxlan tunnel src 10.100.0.10 dst 10.100.0.1 vni 100

# Set up NAT44 for your actual IPs  
docker exec security-processor vppctl nat44 add static mapping local 100.104.12.3 8081 external 10.102.0.10 8081
```

## Production Monitoring

### Performance Metrics
```bash
# Real-time VPP stats
watch -n 1 'for container in traffic-ingress security-processor analytics-destination; do
    echo "=== $container ===" 
    docker exec $container vppctl show runtime | head -5
done'

# Interface throughput monitoring
watch -n 1 'for container in traffic-ingress security-processor analytics-destination; do
    docker exec $container vppctl show interface | grep -E "(rx|tx) packets"
done'
```

### Logging and Alerting
```bash  
# Configure log rotation
echo "/var/log/vpp/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 644 root root
}" | sudo tee /etc/logrotate.d/vpp

# Monitor packet drops
for container in traffic-ingress security-processor analytics-destination; do
    docker exec $container vppctl show errors | grep -v " 0 "
done
```

## Production Validation

### Traffic Verification
```bash
# Enable detailed tracing for production validation
for container in traffic-ingress security-processor analytics-destination; do
    docker exec $container vppctl trace add af-packet-input 100
done

# Send your actual traffic patterns
# Monitor packet processing end-to-end
docker exec traffic-ingress vppctl show vxlan tunnel
docker exec security-processor vppctl show nat44 sessions  
docker exec analytics-destination vppctl show interface tap0
```

### Performance Baselines
```bash
# Establish performance baselines
echo "=== Production Performance Baselines ===" > /var/log/vpp-performance.log
date >> /var/log/vpp-performance.log

for container in traffic-ingress security-processor analytics-destination; do
    echo "=== $container Performance ===" >> /var/log/vpp-performance.log
    docker exec $container vppctl show runtime >> /var/log/vpp-performance.log
    docker exec $container vppctl show memory >> /var/log/vpp-performance.log
    echo "" >> /var/log/vpp-performance.log
done
```

## Scaling Considerations

### Horizontal Scaling
```bash
# Create multiple VPP chain instances for load balancing
for i in {1..3}; do
    cp config-production.json config-instance-$i.json
    # Update IP addresses for each instance
    sed -i "s/10.100.0.10/10.100.0.$((10+i))/g" config-instance-$i.json
done
```

### Load Balancing
```bash
# Use ECMP or load balancer to distribute traffic
# Example with HAProxy configuration:
cat >> /etc/haproxy/haproxy.cfg << EOF
frontend vpp_frontend
    bind *:8081
    bind *:31765
    default_backend vpp_backend

backend vpp_backend
    balance roundrobin
    server vpp1 10.100.0.11:8081 check
    server vpp2 10.100.0.12:8081 check  
    server vpp3 10.100.0.13:8081 check
EOF
```

## Security Hardening

```bash
# Container security
for container in traffic-ingress security-processor analytics-destination; do
    docker exec $container iptables -I INPUT -p tcp --dport 22 -j DROP
    docker exec $container iptables -I INPUT -i lo -j ACCEPT
    docker exec $container iptables -P INPUT DROP
done

# Network segmentation  
sudo iptables -A FORWARD -s 10.100.0.0/24 -d 10.101.0.0/24 -j ACCEPT
sudo iptables -A FORWARD -s 10.101.0.0/24 -d 10.102.0.0/24 -j ACCEPT
sudo iptables -A FORWARD -j DROP
```

## Maintenance and Operations

### Health Checks
```bash
#!/bin/bash
# Production health check script
for container in traffic-ingress security-processor analytics-destination; do
    if ! docker exec $container vppctl show version >/dev/null 2>&1; then
        echo "ALERT: $container VPP not responding"
        # Add alerting logic (email, Slack, PagerDuty)
    fi
done
```

### Backup and Recovery
```bash
# Backup VPP configuration
mkdir -p /backup/vpp/$(date +%Y%m%d)
for container in traffic-ingress security-processor analytics-destination; do
    docker exec $container vppctl show config > /backup/vpp/$(date +%Y%m%d)/$container-config.txt
done
```

This migration guide transforms your test environment into a production-ready system that can handle your real traffic patterns with monitoring, security, and scalability.