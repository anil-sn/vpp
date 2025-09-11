# AWS Traffic Mirroring → GKE Production Deployment Guide

## Architecture Overview

This VPP-based solution solves the critical **Layer 2 MAC address forwarding problem** in AWS Traffic Mirroring by implementing MAC address rewriting and source IP preservation for NetFlow/sFlow/IPFIX data forwarded to GKE services.

### The Problem We Solve

**AWS Traffic Mirroring Challenge:**
- AWS Traffic Mirroring encapsulates original packets in VXLAN with original destination MAC addresses
- Linux kernel sees foreign MAC addresses and attempts Layer 2 forwarding  
- AWS ENI security enforces source MAC validation, dropping packets with incorrect source MACs
- Result: Original source IP traffic cannot reach GKE processing services

**Our Solution:**
```
AWS Traffic Mirror → VPP VXLAN Decap → MAC Rewrite → Source IP Preservation → GKE Service
     (VXLAN)           (Layer 2 Fix)    (Layer 3)       (Original IPs)      (NetFlow/sFlow)
```

### Production Architecture

```
┌─────────────────────┐    ┌──────────────────────┐    ┌─────────────────────┐
│   AWS-VXLAN-DECAP   │───▶│  SOURCE-IP-PROCESSOR │───▶│    GKE-FORWARDER    │
│                     │    │                      │    │                     │
│ • VXLAN Decap       │    │ • Source IP Preserve │    │ • Load Balancing    │
│ • MAC Rewrite       │    │ • NAT Bypass         │    │ • Health Checks     │
│ • ENI Compliance    │    │ • Flow Classification│    │ • GKE Integration   │
└─────────────────────┘    └──────────────────────┘    └─────────────────────┘
     10.10.0.10                   10.11.0.20                  10.12.0.20
```

## Production Deployment Steps

### Step 1: AWS Infrastructure Setup

**Create Mirror Target EC2 Instance:**
```bash
# Launch optimized instance for VPP processing
aws ec2 run-instances \\
  --image-id ami-0abcdef1234567890 \\
  --instance-type c5n.4xlarge \\
  --key-name your-key-pair \\
  --security-group-ids sg-vpp-mirror-target \\
  --subnet-id subnet-12345678 \\
  --placement AvailabilityZone=us-east-1a \\
  --ena-support \\
  --sriov-net-support simple \\
  --user-data file://vpp-userdata.sh
```

**Configure Security Group:**
```bash
# Allow VXLAN traffic from Traffic Mirror
aws ec2 authorize-security-group-ingress \\
  --group-id sg-vpp-mirror-target \\
  --protocol udp \\
  --port 4789 \\
  --source-group sg-traffic-mirror-sources

# Allow management access  
aws ec2 authorize-security-group-ingress \\
  --group-id sg-vpp-mirror-target \\
  --protocol tcp \\
  --port 22 \\
  --cidr 10.0.0.0/8
```

**Create Traffic Mirror Target:**
```bash
# Create mirror target pointing to your VPP instance
aws ec2 create-traffic-mirror-target \\
  --network-interface-id eni-12345678 \\
  --description "VPP VXLAN Processor"

# Create mirror filter for NetFlow/sFlow/IPFIX
aws ec2 create-traffic-mirror-filter \\
  --description "NetFlow sFlow IPFIX Traffic"

aws ec2 create-traffic-mirror-filter-rule \\
  --traffic-mirror-filter-id tmf-12345678 \\
  --traffic-direction ingress \\
  --rule-number 100 \\
  --rule-action accept \\
  --protocol udp \\
  --destination-port-range FromPort=2055,ToPort=2055

aws ec2 create-traffic-mirror-filter-rule \\
  --traffic-mirror-filter-id tmf-12345678 \\
  --traffic-direction ingress \\
  --rule-number 200 \\
  --rule-action accept \\
  --protocol udp \\
  --destination-port-range FromPort=6343,ToPort=6343
```

### Step 2: GKE Cluster Setup

**Create GKE Cluster:**
```bash
# Create cluster for NetFlow processing
gcloud container clusters create netflow-processing-cluster \\
  --region us-central1 \\
  --node-locations us-central1-a,us-central1-b,us-central1-c \\
  --num-nodes 3 \\
  --machine-type c2-standard-4 \\
  --enable-network-policy \\
  --enable-ip-alias \\
  --cluster-version 1.28 \\
  --enable-autorepair \\
  --enable-autoupgrade
```

**Deploy NetFlow Processing Service:**
```yaml
# netflow-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: netflow-processor
  namespace: default
  annotations:
    cloud.google.com/backend-config: '{"default": "netflow-backendconfig"}'
spec:
  type: LoadBalancer
  loadBalancerSourceRanges:
    - "10.10.0.0/16"  # Allow VPP forwarder traffic
  externalTrafficPolicy: Local  # Preserve source IPs
  ports:
  - port: 2055
    targetPort: 2055 
    protocol: UDP
    name: netflow
  - port: 6343
    targetPort: 6343
    protocol: UDP
    name: sflow  
  - port: 4739
    targetPort: 4739
    protocol: UDP
    name: ipfix
  selector:
    app: netflow-processor

---
apiVersion: apps/v1
kind: Deployment  
metadata:
  name: netflow-processor
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: netflow-processor
  template:
    metadata:
      labels:
        app: netflow-processor
    spec:
      containers:
      - name: netflow-processor
        image: gcr.io/your-project/netflow-processor:latest
        ports:
        - containerPort: 2055
          protocol: UDP
        - containerPort: 6343
          protocol: UDP  
        - containerPort: 4739
          protocol: UDP
        env:
        - name: PRESERVE_SOURCE_IP
          value: "true"
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi" 
            cpu: "1000m"
```

### Step 3: VPP Chain Deployment

**Deploy VPP Configuration:**
```bash
# On your Mirror Target EC2 instance
cd /opt/vpp-chain

# Use AWS-GKE production configuration
cp config-aws-gke-production.json config.json

# Update GKE service endpoints in config
export GKE_SERVICE_IP=$(kubectl get svc netflow-processor -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
sed -i "s/10.13.0.100/$GKE_SERVICE_IP/g" config.json

# Setup VPP chain  
sudo python3 src/main.py cleanup
sudo python3 src/main.py setup --force

# Verify deployment
python3 src/main.py status
```

**Configure AWS-Specific Optimizations:**
```bash
# Enable SR-IOV on EC2 instance
sudo modprobe vfio-pci
echo 'vfio-pci' | sudo tee -a /etc/modules

# Configure CPU isolation for VPP
echo 'GRUB_CMDLINE_LINUX="isolcpus=2-7 nohz_full=2-7 rcu_nocbs=2-7 intel_iommu=on"' | sudo tee -a /etc/default/grub
sudo update-grub

# Configure huge pages
echo 2048 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
echo 'vm.nr_hugepages=2048' | sudo tee -a /etc/sysctl.conf

# Optimize network interfaces
sudo ethtool -C eth0 rx 4096 tx 4096
sudo ethtool -G eth0 rx 4096 tx 4096
sudo ethtool -K eth0 gro on lro on tso on
```

### Step 4: Production Testing & Validation

**Test AWS Traffic Mirror → VPP Pipeline:**
```bash
# Create Traffic Mirror Session  
aws ec2 create-traffic-mirror-session \\
  --network-interface-id eni-source-interface \\
  --traffic-mirror-target-id tmt-12345678 \\
  --traffic-mirror-filter-id tmf-12345678 \\
  --session-number 1

# Validate VXLAN decapsulation
sudo python3 src/main.py debug aws-vxlan-decap "show vxlan tunnel"
sudo python3 src/main.py debug aws-vxlan-decap "show bridge-domain 1 detail"

# Verify MAC address rewriting
docker exec aws-vxlan-decap vppctl show l2fib all
docker exec aws-vxlan-decap vppctl show interface address
```

**Test Source IP Preservation:**
```bash  
# Generate test NetFlow traffic
nfcapd -T all -l /tmp -p 2055 &
nfgen -d 100.104.12.3 -p 2055 -c 100

# Verify source IP preservation through pipeline
sudo python3 src/main.py debug source-ip-processor "show nat44 sessions"
sudo python3 src/main.py debug gke-forwarder "show lb vips"

# Check GKE service receives original source IPs
kubectl logs deployment/netflow-processor | grep "Source IP"
```

**End-to-End Validation:**
```bash
# Enable comprehensive tracing
for container in aws-vxlan-decap source-ip-processor gke-forwarder; do
    docker exec $container vppctl trace add af-packet-input 100
done

# Generate real traffic and trace through pipeline
# 1. AWS Traffic Mirror sends VXLAN to VPP
# 2. VPP decapsulates and rewrites MACs  
# 3. Source IPs preserved through NAT bypass
# 4. Traffic reaches GKE with original source IPs

# View traces
docker exec aws-vxlan-decap vppctl show trace
docker exec source-ip-processor vppctl show trace  
docker exec gke-forwarder vppctl show trace
```

## Production Monitoring

### Performance Metrics
```bash
# Create monitoring dashboard
cat > /opt/vpp-monitoring.sh << 'EOF'
#!/bin/bash
while true; do
    echo "$(date): AWS-GKE VPP Pipeline Metrics"
    echo "========================================"
    
    # VXLAN decapsulation stats
    echo "VXLAN Tunnel Stats:"
    docker exec aws-vxlan-decap vppctl show vxlan tunnel | grep -E "(rx|tx) packets"
    
    # Source IP preservation stats  
    echo "NAT44 Sessions (should be minimal for preserved traffic):"
    docker exec source-ip-processor vppctl show nat44 sessions | wc -l
    
    # GKE forwarding stats
    echo "Load Balancer to GKE:"
    docker exec gke-forwarder vppctl show lb vips
    
    # Performance counters
    echo "Interface Performance:"
    for container in aws-vxlan-decap source-ip-processor gke-forwarder; do
        echo "=== $container ==="
        docker exec $container vppctl show runtime | head -3
    done
    
    sleep 60
done
EOF
chmod +x /opt/vpp-monitoring.sh
```

### Alerting Setup
```bash
# Configure CloudWatch metrics for AWS
aws logs create-log-group --log-group-name /aws/vpp/traffic-processing

# Set up alarms for packet drops
aws cloudwatch put-metric-alarm \\
  --alarm-name "VPP-Packet-Drops" \\
  --alarm-description "VPP packet drops detected" \\
  --metric-name PacketDrops \\
  --namespace AWS/VPP \\
  --statistic Sum \\
  --period 300 \\
  --threshold 100 \\
  --comparison-operator GreaterThanThreshold
```

## Troubleshooting Guide

### Common Issues

**1. VXLAN Decapsulation Failures**
```bash
# Check VXLAN tunnel configuration
docker exec aws-vxlan-decap vppctl show vxlan tunnel
# Verify VNI matches AWS Traffic Mirror

# Check bridge domain learning
docker exec aws-vxlan-decap vppctl show bridge-domain 1
# Should show learn=0 (disabled for AWS)
```

**2. MAC Address Forwarding Problems**  
```bash
# Verify MAC rewriting is working
docker exec aws-vxlan-decap vppctl show interface address
# Should show correct ENI MAC addresses

# Check L2 forwarding stats
docker exec aws-vxlan-decap vppctl show l2fib verbose
```

**3. Source IP Not Preserved**
```bash
# Verify NAT bypass for flow monitoring traffic
docker exec source-ip-processor vppctl show classify tables
docker exec source-ip-processor vppctl show acl-plugin acl

# Check policy routing
docker exec source-ip-processor vppctl show ip fib table 1
```

**4. GKE Service Connectivity Issues**
```bash
# Verify load balancer health
docker exec gke-forwarder vppctl show lb vips verbose
docker exec gke-forwarder vppctl show health-check

# Check GKE service endpoints
kubectl get endpoints netflow-processor -o yaml
```

This production deployment solves the AWS Traffic Mirroring Layer 2 MAC address problem while preserving original source IPs for your NetFlow/sFlow/IPFIX processing in GKE.