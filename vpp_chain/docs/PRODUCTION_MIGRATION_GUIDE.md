# Production Migration Guide: VPP Multi-Container Chain Deployment

## Executive Summary

This guide provides step-by-step instructions for deploying VPP multi-container chains into production environments. The approach emphasizes comprehensive environment analysis, customized configuration generation, and gradual traffic migration to ensure zero-downtime deployment.

### Migration Approach Overview
- **Environment Discovery**: Automated analysis of existing infrastructure
- **Custom Configuration**: Tailored production.json based on discovered parameters  
- **Gradual Migration**: Incremental traffic redirection with rollback capability
- **Production Validation**: 90% packet delivery success rate with comprehensive monitoring

## Prerequisites

### System Requirements
- **Operating System**: Linux (Ubuntu 20.04 or CentOS 8 minimum)
- **Hardware**: Minimum 4 CPU cores, 8GB RAM, 20GB storage
- **Network**: Root access required for traffic redirection
- **Docker**: Version 20.10 or higher with Docker Compose
- **Python**: Version 3.8 or higher with pip

### Required Access Levels
- Root access via sudo for network configuration
- Docker daemon access (user in docker group)
- Ability to modify iptables rules
- Permission to create and manage systemd services

### Pre-Migration Checklist
- [ ] Backup existing network configuration
- [ ] Document current traffic patterns
- [ ] Identify maintenance windows
- [ ] Prepare rollback procedures
- [ ] Configure monitoring and alerting

## Phase 1: Environment Discovery and Analysis

### Step 1.1: Install Discovery Tools

Execute the following commands to install required discovery utilities:

```bash
# Navigate to project directory
cd /path/to/vpp_chain

# Install system dependencies
sudo apt update && sudo apt install -y \
    docker.io python3 python3-pip jq curl net-tools \
    iptables-persistent tcpdump tshark

# Install Python dependencies
pip3 install scapy netifaces psutil

# Verify installations
docker --version
python3 --version
```

### Step 1.2: Run Environment Discovery

Use the automated discovery tool to analyze your infrastructure:

```bash
# Run comprehensive environment discovery
./tools/discovery/environment_discovery.sh -v

# Wait for discovery to complete (typically 5-10 minutes)
# Discovery results will be saved to /tmp/vpp_discovery_YYYYMMDD_HHMMSS/

# Locate the discovery directory
DISCOVERY_DIR=$(ls -1dt /tmp/vpp_discovery_* | head -1)
echo "Discovery completed. Results in: $DISCOVERY_DIR"

# Review the discovery report
cat "$DISCOVERY_DIR/discovery_report.txt"
```

### Step 1.3: Analyze Discovery Results

Review the generated discovery report and verify the following key parameters:

**System Information Verification**:
```bash
# Review system specifications
grep -A 10 "SYSTEM INFORMATION" "$DISCOVERY_DIR/discovery_report.txt"

# Verify minimum requirements are met:
# - CPU Cores: 4 or more
# - Memory: 8GB or more  
# - Disk Space: 20GB or more available
```

**Network Configuration Review**:
```bash
# Review network interfaces and IP assignments
grep -A 20 "NETWORK CONFIGURATION" "$DISCOVERY_DIR/discovery_report.txt"

# Document primary interface and IP range
# Ensure no conflicts with proposed VPP networks (172.20.x.x)
```

**Cloud Environment Detection**:
```bash
# Check detected cloud provider
grep -A 10 "CLOUD ENVIRONMENT" "$DISCOVERY_DIR/discovery_report.txt"

# Note: This affects monitoring and integration configuration
```

## Phase 2: Production Configuration Generation

### Step 2.1: Generate Custom Production Configuration

Create production-specific configuration based on discovered environment:

```bash
# Generate production configuration
python3 tools/config-generator/production_config_generator.py \
    --discovery-dir "$DISCOVERY_DIR" \
    --output production.json

# Validate generated configuration
python3 -m json.tool production.json > /dev/null
echo "Configuration validation: PASSED"

# Review key configuration sections
jq '.modes.production.networks' production.json
jq '.modes.production.containers | keys' production.json
```

### Step 2.2: Customize Production Settings

Review and customize the generated configuration for your environment:

```bash
# Edit production configuration if needed
vim production.json

# Key sections to review:
# 1. Network subnets - ensure no conflicts
# 2. Resource allocation - adjust based on system capacity
# 3. IPsec keys - MUST be changed for production
# 4. Monitoring configuration - adapt to your monitoring stack
```

**Critical Security Configuration**:
```bash
# MANDATORY: Replace default IPsec keys
# Search for "PRODUCTION_KEY_ROTATION_REQUIRED" in production.json
# Replace with strong 32-character hexadecimal keys

grep -n "PRODUCTION_KEY_ROTATION_REQUIRED" production.json
# Update each instance with unique production keys
```

### Step 2.3: Validate Production Configuration

Perform comprehensive validation before deployment:

```bash
# Run configuration validation
python3 tools/config-generator/production_config_generator.py \
    --discovery-dir "$DISCOVERY_DIR" \
    --validate-only

# Check for configuration conflicts
python3 src/utils/config_manager.py --config production.json --validate

# Verify network assignments don't conflict with existing infrastructure
python3 -c "
import json
with open('production.json') as f:
    config = json.load(f)
    for net in config['modes']['production']['networks']:
        print(f'Network: {net[\"name\"]} - {net[\"subnet\"]}')
"
```

## Phase 3: Pre-Deployment Validation

### Step 3.1: System Readiness Check

Verify all prerequisites are met before deployment:

```bash
# Create pre-deployment validation script
cat > pre_deployment_check.sh << 'EOF'
#!/bin/bash
set -e

echo "=== PRE-DEPLOYMENT VALIDATION ==="

# System resource check
CPU_CORES=$(nproc)
MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')

echo "System Resources:"
echo "  CPU Cores: $CPU_CORES (minimum: 4)"
echo "  Memory: ${MEMORY_GB}GB (minimum: 8GB)"  
echo "  Disk Space: ${DISK_GB}GB (minimum: 20GB)"

# Validate minimum requirements
[ $CPU_CORES -ge 4 ] || { echo "ERROR: Insufficient CPU cores"; exit 1; }
[ $MEMORY_GB -ge 8 ] || { echo "ERROR: Insufficient memory"; exit 1; }
[ $DISK_GB -ge 20 ] || { echo "ERROR: Insufficient disk space"; exit 1; }

# Docker service check
systemctl is-active docker >/dev/null || { echo "ERROR: Docker not running"; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERROR: Docker not accessible"; exit 1; }

# Network port availability check
for port in 4789 2055 8081; do
    if ss -tuln | grep -q ":$port "; then
        echo "WARNING: Port $port already in use"
    fi
done

# VPP image availability
docker pull vppproject/vpp:v24.10 >/dev/null 2>&1 || { echo "ERROR: Cannot access VPP Docker image"; exit 1; }

echo "All pre-deployment checks passed"
EOF

chmod +x pre_deployment_check.sh
./pre_deployment_check.sh
```

### Step 3.2: Backup Current Configuration

Create comprehensive backup before making any changes:

```bash
# Create backup directory
BACKUP_DIR="/opt/vpp_backup_$(date +%Y%m%d_%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"

# Backup network configuration
sudo cp /etc/netplan/* "$BACKUP_DIR/" 2>/dev/null || true
sudo cp /etc/network/interfaces "$BACKUP_DIR/" 2>/dev/null || true

# Backup iptables rules
sudo iptables-save > "$BACKUP_DIR/iptables.rules"
sudo ip6tables-save > "$BACKUP_DIR/ip6tables.rules"

# Backup routing tables
ip route show > "$BACKUP_DIR/routes.txt"
ip addr show > "$BACKUP_DIR/interfaces.txt"

# Document running services
systemctl list-units --state=running > "$BACKUP_DIR/running_services.txt"

echo "Backup completed: $BACKUP_DIR"
```

## Phase 4: Production Deployment

### Step 4.1: Deploy VPP Containers

Deploy the multi-container chain using production configuration:

```bash
# Clean any existing deployment
sudo python3 src/main.py cleanup

# Deploy with production configuration
sudo python3 src/main.py setup --mode production --force

# Monitor deployment progress
python3 src/main.py status

# Verify all containers are running
docker ps --filter "name=vxlan-processor" --filter "name=security-processor" --filter "name=destination"
```

### Step 4.2: Validate Container Health

Perform comprehensive health checks on deployed containers:

```bash
# Check container health status
for container in vxlan-processor security-processor destination; do
    echo "=== $container Health Check ==="
    
    # Container status
    docker inspect "$container" | jq '.[0].State.Health.Status'
    
    # VPP responsiveness
    docker exec "$container" vppctl show version
    
    # Interface configuration
    docker exec "$container" vppctl show interface addr
    
    # Memory usage
    docker exec "$container" vppctl show memory
    
    echo ""
done
```

### Step 4.3: Network Connectivity Verification

Test inter-container connectivity before enabling traffic:

```bash
# Run connectivity tests
sudo python3 src/main.py test --type connectivity

# Manual connectivity verification
echo "Testing VXLAN-PROCESSOR to SECURITY-PROCESSOR:"
docker exec vxlan-processor ping -c 3 172.20.101.20

echo "Testing SECURITY-PROCESSOR to DESTINATION:"
docker exec security-processor ping -c 3 172.20.102.20

# Verify VPP neighbor tables
for container in vxlan-processor security-processor destination; do
    echo "=== $container Neighbor Table ==="
    docker exec "$container" vppctl show ip neighbors
done
```

## Phase 5: Traffic Migration and Validation

### Step 5.1: Configure Traffic Redirection

Implement gradual traffic redirection with monitoring:

```bash
# Create traffic redirection script
cat > traffic_redirection.sh << 'EOF'
#!/bin/bash
set -e

# Configuration
VPP_CONTAINER_IP=$(docker inspect vxlan-processor | jq -r '.[0].NetworkSettings.Networks | to_entries | .[0].value.IPAddress')
BACKUP_FILE="/opt/iptables_backup_$(date +%Y%m%d_%H%M%S).rules"

echo "Starting gradual traffic redirection to $VPP_CONTAINER_IP"

# Backup current iptables
iptables-save > "$BACKUP_FILE"
echo "Iptables backed up to: $BACKUP_FILE"

# Function to check VPP health
check_vpp_health() {
    if ! docker exec vxlan-processor vppctl show version >/dev/null 2>&1; then
        echo "ERROR: VPP health check failed"
        return 1
    fi
    
    # Check packet processing success rate
    local success_rate=$(sudo python3 src/main.py test --type traffic 2>/dev/null | 
                        grep "End-to-end delivery rate" | 
                        sed 's/.*: \([0-9.]*\)%.*/\1/')
    
    if [ -n "$success_rate" ] && (( $(echo "$success_rate < 85" | bc -l) )); then
        echo "ERROR: Packet success rate below 85%: $success_rate%"
        return 1
    fi
    
    return 0
}

# Gradual traffic increase
PERCENTAGES=(0.01 0.05 0.10 0.25 0.50 0.75 1.00)
for pct in "${PERCENTAGES[@]}"; do
    echo "Setting traffic redirection to $(echo "$pct * 100" | bc)%"
    
    # Remove existing rule
    iptables -t nat -D PREROUTING -p udp --dport 4789 -j DNAT --to-destination "$VPP_CONTAINER_IP:4789" 2>/dev/null || true
    
    # Add new rule with updated percentage
    if [ "$pct" = "1.00" ]; then
        # 100% - remove statistical match for full redirection
        iptables -t nat -A PREROUTING -p udp --dport 4789 -j DNAT --to-destination "$VPP_CONTAINER_IP:4789"
    else
        iptables -t nat -A PREROUTING -p udp --dport 4789 -m statistic --mode random --probability "$pct" -j DNAT --to-destination "$VPP_CONTAINER_IP:4789"
    fi
    
    # Wait for traffic to stabilize
    sleep 60
    
    # Health check
    if ! check_vpp_health; then
        echo "CRITICAL: Health check failed at $(echo "$pct * 100" | bc)% - initiating rollback"
        iptables-restore < "$BACKUP_FILE"
        exit 1
    fi
    
    echo "Traffic redirection at $(echo "$pct * 100" | bc)% - HEALTHY"
    
    # Progressive wait times (longer waits as percentage increases)
    if [ "$pct" != "1.00" ]; then
        wait_time=$(echo "$pct * 600 + 300" | bc | cut -d. -f1)
        echo "Monitoring for ${wait_time} seconds before next increment"
        sleep "$wait_time"
    fi
done

# Save final configuration
iptables-save > /etc/iptables/rules.v4

echo "Traffic redirection completed successfully - 100% traffic now processed by VPP"
EOF

chmod +x traffic_redirection.sh
```

### Step 5.2: Execute Gradual Traffic Migration

Run the traffic redirection with careful monitoring:

```bash
# Start traffic redirection (this will take 2-4 hours for full migration)
./traffic_redirection.sh

# Monitor progress in separate terminal
watch -n 30 'docker exec vxlan-processor vppctl show interface | grep -A 2 host-eth0'
```

### Step 5.3: Production Traffic Validation

Validate production traffic processing:

```bash
# Enable comprehensive packet tracing
for container in vxlan-processor security-processor destination; do
    docker exec "$container" vppctl clear trace
    docker exec "$container" vppctl trace add af-packet-input 50
done

# Let traffic flow for 5 minutes with tracing
sleep 300

# Analyze packet processing traces
echo "=== VXLAN-PROCESSOR Packet Processing ==="
docker exec vxlan-processor vppctl show trace | head -50

echo "=== SECURITY-PROCESSOR Packet Processing ==="
docker exec security-processor vppctl show trace | head -50

echo "=== DESTINATION Packet Processing ==="
docker exec destination vppctl show trace | head -50

# Check interface statistics
for container in vxlan-processor security-processor destination; do
    echo "=== $container Interface Statistics ==="
    docker exec "$container" vppctl show interface
    docker exec "$container" vppctl show errors
done
```

## Phase 6: Production Monitoring and Maintenance

### Step 6.1: Configure Production Monitoring

Set up comprehensive monitoring for the production deployment:

```bash
# Create monitoring script
cat > /usr/local/bin/vpp_production_monitor.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/vpp_production.log"
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEMORY=80
ALERT_THRESHOLD_PACKET_LOSS=5

log_with_timestamp() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Container health monitoring
for container in vxlan-processor security-processor destination; do
    if ! docker ps | grep -q "$container.*Up"; then
        log_with_timestamp "CRITICAL: $container is not running"
        # Add your alerting mechanism here (email, Slack, etc.)
        continue
    fi
    
    # VPP responsiveness check
    if ! docker exec "$container" vppctl show version >/dev/null 2>&1; then
        log_with_timestamp "CRITICAL: $container VPP is unresponsive"
        # Add your alerting mechanism here
        continue
    fi
    
    # Resource usage monitoring
    CPU_PERCENT=$(docker stats --no-stream --format "table {{.CPUPerc}}" "$container" | tail -1 | sed 's/%//')
    MEM_USAGE=$(docker stats --no-stream --format "table {{.MemUsage}}" "$container" | tail -1)
    
    if (( $(echo "$CPU_PERCENT > $ALERT_THRESHOLD_CPU" | bc -l) )); then
        log_with_timestamp "WARNING: $container CPU usage: $CPU_PERCENT%"
    fi
    
    log_with_timestamp "INFO: $container - CPU: $CPU_PERCENT%, Memory: $MEM_USAGE"
done

# Packet processing rate monitoring
PACKET_STATS=$(sudo python3 src/main.py test --type traffic 2>/dev/null | grep "End-to-end delivery rate" | sed 's/.*: \([0-9.]*\)%.*/\1/')

if [ -n "$PACKET_STATS" ]; then
    if (( $(echo "$PACKET_STATS < 90" | bc -l) )); then
        log_with_timestamp "WARNING: Packet delivery rate below target: $PACKET_STATS%"
    else
        log_with_timestamp "INFO: Packet delivery rate: $PACKET_STATS%"
    fi
fi

# Interface error monitoring
for container in vxlan-processor security-processor destination; do
    ERROR_COUNT=$(docker exec "$container" vppctl show errors | grep -v "^$" | wc -l)
    if [ "$ERROR_COUNT" -gt 0 ]; then
        log_with_timestamp "WARNING: $container has $ERROR_COUNT interface errors"
        docker exec "$container" vppctl show errors >> "$LOG_FILE"
    fi
done
EOF

chmod +x /usr/local/bin/vpp_production_monitor.sh

# Set up monitoring cron job (every 5 minutes)
echo "*/5 * * * * /usr/local/bin/vpp_production_monitor.sh" | sudo crontab -

# Set up log rotation
sudo cat > /etc/logrotate.d/vpp_production << 'EOF'
/var/log/vpp_production.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    create 644 root root
}
EOF
```

### Step 6.2: Operational Procedures

Create standard operational procedures for production management:

```bash
# Daily health check script
cat > /usr/local/bin/vpp_daily_healthcheck.sh << 'EOF'
#!/bin/bash
echo "=== VPP Production Daily Health Check - $(date) ==="

# 1. Container status verification
echo "1. Container Health Status:"
for container in vxlan-processor security-processor destination; do
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container.*Up"; then
        uptime=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$container" | awk '{print $3" "$4}')
        echo "   HEALTHY: $container ($uptime)"
    else
        echo "   FAILED: $container - Not running"
        exit 1
    fi
done

# 2. Resource utilization check
echo "2. Resource Utilization:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

# 3. Network interface status
echo "3. Network Interface Status:"
for container in vxlan-processor security-processor destination; do
    echo "   $container interfaces:"
    docker exec "$container" vppctl show interface | grep -E "^\s*(host-|tap|vxlan|ipip)" | head -10
done

# 4. Traffic processing verification
echo "4. Traffic Processing Test:"
TRAFFIC_RESULT=$(sudo python3 src/main.py test --type traffic 2>/dev/null | grep "End-to-end delivery rate")
echo "   $TRAFFIC_RESULT"

# 5. System resource status
echo "5. System Resources:"
echo "   Load Average: $(uptime | cut -d',' -f3-)"
echo "   Memory Usage: $(free -h | grep '^Mem:' | awk '{print "Used: "$3" / Total: "$2" ("$3/$2*100"% used)"}')"
echo "   Disk Usage: $(df -h / | tail -1 | awk '{print $5" used ("$3" / "$2")"}')"

# 6. Network connectivity verification
echo "6. Network Connectivity:"
if docker exec vxlan-processor ping -c 1 172.20.101.20 >/dev/null 2>&1; then
    echo "   PASSED: VXLAN-PROCESSOR to SECURITY-PROCESSOR"
else
    echo "   FAILED: VXLAN-PROCESSOR to SECURITY-PROCESSOR"
fi

if docker exec security-processor ping -c 1 172.20.102.20 >/dev/null 2>&1; then
    echo "   PASSED: SECURITY-PROCESSOR to DESTINATION"  
else
    echo "   FAILED: SECURITY-PROCESSOR to DESTINATION"
fi

echo "=== Daily Health Check Complete ==="
EOF

chmod +x /usr/local/bin/vpp_daily_healthcheck.sh

# Schedule daily health check at 8 AM
echo "0 8 * * * /usr/local/bin/vpp_daily_healthcheck.sh >> /var/log/vpp_daily_healthcheck.log 2>&1" | sudo crontab -l | sudo crontab -
```

### Step 6.3: Emergency Procedures

Establish emergency rollback and recovery procedures:

```bash
# Emergency rollback script
cat > /usr/local/bin/vpp_emergency_rollback.sh << 'EOF'
#!/bin/bash
set -e

TIMESTAMP=$(date '+%Y-%m-%d_%H:%M:%S')
LOG_FILE="/var/log/vpp_emergency_rollback.log"

log_action() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

log_action "EMERGENCY ROLLBACK INITIATED"

# 1. Immediate traffic restoration
log_action "Step 1: Restoring traffic routing"
BACKUP_FILE=$(ls -1t /opt/iptables_backup_*.rules 2>/dev/null | head -1)
if [ -f "$BACKUP_FILE" ]; then
    iptables-restore < "$BACKUP_FILE"
    log_action "Traffic routing restored from: $BACKUP_FILE"
else
    log_action "ERROR: No iptables backup found - manual intervention required"
fi

# 2. Stop VPP containers
log_action "Step 2: Stopping VPP containers"
sudo python3 src/main.py cleanup
log_action "VPP containers stopped"

# 3. Verify traffic restoration
log_action "Step 3: Verifying traffic restoration"
sleep 30

# Check if original services are receiving traffic
if ss -tuln | grep -q ":4789"; then
    log_action "SUCCESS: Traffic restored to original destination"
else
    log_action "WARNING: No VXLAN traffic detected on port 4789"
fi

# 4. System health check
log_action "Step 4: System health verification"
echo "System load: $(uptime | cut -d',' -f3-)" >> "$LOG_FILE"
echo "Memory usage: $(free -h | grep '^Mem:' | awk '{print $3"/"$2}')" >> "$LOG_FILE"
echo "Disk usage: $(df -h / | tail -1 | awk '{print $5}')" >> "$LOG_FILE"

log_action "EMERGENCY ROLLBACK COMPLETED"
log_action "NEXT STEPS: 1) Verify service restoration 2) Investigate failure cause 3) Plan re-deployment"

echo ""
echo "Emergency rollback completed. Check log: $LOG_FILE"
echo "Verify your services are operating normally."
EOF

chmod +x /usr/local/bin/vpp_emergency_rollback.sh

# Create emergency contact information
cat > /usr/local/bin/emergency_contacts.txt << 'EOF'
VPP Multi-Container Chain Emergency Contacts
==========================================

Primary On-Call: [Your primary contact]
Secondary: [Your secondary contact]
Escalation: [Your escalation contact]

Emergency Procedures:
1. Run: /usr/local/bin/vpp_emergency_rollback.sh
2. Verify service restoration
3. Contact on-call team
4. Document incident details

Log Locations:
- Production logs: /var/log/vpp_production.log
- Daily health checks: /var/log/vpp_daily_healthcheck.log  
- Emergency rollback: /var/log/vpp_emergency_rollback.log

Configuration Backups:
- Network config: /opt/vpp_backup_*/
- Iptables rules: /opt/iptables_backup_*.rules
EOF
```

## Success Criteria and Validation

### Production Readiness Checklist
- [ ] All containers running and healthy for 24+ hours
- [ ] Packet delivery rate consistently above 90%
- [ ] No interface errors or packet drops
- [ ] System resource usage within acceptable limits
- [ ] Monitoring and alerting operational
- [ ] Emergency procedures tested and documented
- [ ] Backup and rollback procedures validated

### Performance Targets
- **Packet Delivery Rate**: 90% minimum (target: 95%+)
- **Processing Latency**: Under 50ms P99
- **System Resource Usage**: Under 80% CPU and memory
- **Container Uptime**: 99.9% availability
- **Error Rate**: Less than 0.1% packet processing errors

### Ongoing Maintenance Schedule
- **Daily**: Automated health checks and monitoring
- **Weekly**: Manual validation of packet processing statistics
- **Monthly**: Review and rotate IPsec keys if configured
- **Quarterly**: Performance benchmarking and optimization review

This production migration guide provides a comprehensive, step-by-step approach for safely deploying VPP multi-container chains in production environments with minimal risk and maximum reliability.