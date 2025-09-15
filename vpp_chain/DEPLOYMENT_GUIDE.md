# Multi-Cloud VPP Chain Deployment Guide

## Overview
Deploy high-performance VPP processing chain across AWS and GCP VMs for packet processing from ens5 ingress to ens6 egress with cross-cloud VPN connectivity.

**Architecture:**
```
AWS VM: [ens5] → [VXLAN-PROCESSOR] → [SECURITY-PROCESSOR] → [VPN]
                                                             ↓
GCP VM: [VPN] → [DESTINATION] → [TAP Interface]
```

## Prerequisites

**AWS VM:**
- VM with ens5 and ens6 interfaces
- Root/sudo access
- Internet connectivity
- VPN connectivity to GCP

**GCP VM:**
- VM with network interfaces
- Root/sudo access  
- Internet connectivity
- VPN connectivity to AWS

**Cross-Cloud:**
- VPN tunnel established between AWS and GCP
- Routing configured for cross-cloud communication
- Firewall rules allow VPP traffic (ports 500, 4500, 4789)

## Step 1: Repository Setup

### On AWS VM:
```bash
# Connect and setup
ssh user@aws-vm-ip
sudo su -
cd /opt
git clone <repository-url> vpp_chain
cd vpp_chain
```

### On GCP VM:
```bash  
# Connect and setup
ssh user@gcp-vm-ip
sudo su -
cd /opt
git clone <repository-url> vpp_chain
cd vpp_chain
```

## Step 2: Generate Configuration Files

Run the interactive configuration generator (choose ONE location):

```bash
cd /opt/vpp_chain
python3 configure_multicloud_deployment.py
```

### Configuration Input Required:

**AWS Environment:**
```
AWS Region: us-west-2
AWS Availability Zone: us-west-2c
AWS Instance Type: t3.large
AWS VPC ID: vpc-xxxxxxxxx
AWS Private Subnet ID: subnet-xxxxxxxxx
Primary Interface Name: ens5
Secondary Interface Name: ens6
VXLAN Processing Network: 192.168.100.0/24
Security Processing Network: 192.168.101.0/24
```

**GCP Environment:**
```
GCP Project ID: my-project
GCP Region: us-central1
GCP Zone: us-central1-a
GCP Instance Type: e2-standard-2
GCP VPC Network Name: default
GCP Subnet Name: default
GCP VM Internal IP/CIDR: 10.0.1.100/24
TAP Interface Network: 10.0.3.0/24
TAP Interface IP: 10.0.3.1
```

**Cross-Cloud Connectivity:**
```
Connectivity method: 1 (VPN Gateway)
Cross-cloud Transit Network: 192.168.200.0/24
AWS Security Processor → GCP IP: 192.168.200.1
GCP Destination ← AWS IP: 192.168.200.2
VPN Shared Secret: [your-vpn-secret]
```

**Traffic Configuration:**
```
NAT Inside Network: 10.10.10.0/24
NAT Outside IP: 192.168.200.2
Source UDP Port: any
Destination UDP Port: 2055
```

### Files Generated:
- `production_aws_config.json`
- `production_gcp_config.json` 
- `multicloud_deployment_metadata.json`

## Step 3: Distribute Configuration Files

**If generated on AWS VM:**
```bash
scp production_gcp_config.json gcp-vm:/opt/vpp_chain/
scp multicloud_deployment_metadata.json gcp-vm:/opt/vpp_chain/
```

**If generated on GCP VM:**
```bash
scp production_aws_config.json aws-vm:/opt/vpp_chain/
scp multicloud_deployment_metadata.json aws-vm:/opt/vpp_chain/
```

## Step 4: Deploy AWS Side

### On AWS VM:
```bash
cd /opt/vpp_chain

# Verify configuration exists
ls -la production_aws_config.json

# Make deployment script executable  
chmod +x deploy_aws_multicloud.sh

# Deploy AWS VPP chain
sudo ./deploy_aws_multicloud.sh
```

### Expected AWS Output:
```
AWS Multi-Cloud VPP Chain Deployment
========================================
Deploying: VXLAN-PROCESSOR → SECURITY-PROCESSOR
Target: GCP destination via cross-cloud connection

Configuration file found: /opt/vpp_chain/production_aws_config.json
Verifying AWS Environment...
Installing Dependencies...
Creating Network Backup...
Cleaning Up Existing Containers...
Deploying AWS VPP Chain...

AWS VPP Chain Deployment Complete!
=====================================

Deployed Components:
• VXLAN-PROCESSOR: Handles VXLAN decapsulation + BVI L2→L3
• SECURITY-PROCESSOR: Performs NAT44 + IPsec + Fragmentation
```

### Verify AWS Deployment:
```bash
# Check containers
docker ps --filter "name=vxlan-processor" --filter "name=security-processor"

# Check VPP status
docker exec vxlan-processor vppctl show interface
docker exec security-processor vppctl show interface

# Check VPP configurations
docker exec vxlan-processor vppctl show vxlan tunnel
docker exec security-processor vppctl show nat44 static mappings
docker exec security-processor vppctl show ipsec sa
```

## Step 5: Deploy GCP Side

### On GCP VM:
```bash
cd /opt/vpp_chain

# Verify configuration exists
ls -la production_gcp_config.json

# Make deployment script executable
chmod +x deploy_gcp_multicloud.sh

# Deploy GCP VPP destination
sudo ./deploy_gcp_multicloud.sh
```

### Expected GCP Output:
```
GCP Multi-Cloud VPP Chain Deployment
========================================
Deploying: DESTINATION processor
Receives from: AWS processors via cross-cloud connection

Configuration file found: /opt/vpp_chain/production_gcp_config.json
Verifying GCP Environment...
Installing Dependencies...
Creating Network Backup...
Deploying GCP VPP Destination...

GCP VPP Destination Deployment Complete!
==========================================

Deployed Components:
• DESTINATION: IPsec decryption + packet reassembly + TAP delivery
```

### Verify GCP Deployment:
```bash
# Check container
docker ps --filter "name=destination"

# Check VPP status
docker exec destination vppctl show interface

# Check TAP interface
docker exec destination vppctl show interface tap0

# Check IPsec decryption
docker exec destination vppctl show ipsec sa
```

## Step 6: Validate End-to-End Deployment

### Run Diagnostics on AWS VM:
```bash
cd /opt/vpp_chain
python3 cross_cloud_diagnostics.py
```

### Run Diagnostics on GCP VM:
```bash
cd /opt/vpp_chain
python3 cross_cloud_diagnostics.py
```

### Test Cross-Cloud Connectivity:
```bash
# On AWS VM - test connectivity to GCP
docker exec security-processor ping -c 3 192.168.200.2

# On GCP VM - test connectivity to AWS
docker exec destination ping -c 3 192.168.200.1
```

## Step 7: Enable Traffic Flow Testing

### Enable VPP Packet Tracing:

**On AWS VM:**
```bash
# Clear and enable tracing
docker exec vxlan-processor vppctl clear trace
docker exec vxlan-processor vppctl trace add af-packet-input 10

docker exec security-processor vppctl clear trace
docker exec security-processor vppctl trace add af-packet-input 10
```

**On GCP VM:**
```bash
# Clear and enable tracing  
docker exec destination vppctl clear trace
docker exec destination vppctl trace add af-packet-input 10
```

### Generate Test Traffic (if needed):
```bash
# On AWS VM - generate test packets
python3 src/main.py test --type traffic --config production_aws_config.json
```

### Monitor Traffic Processing:

**Check packet traces:**
```bash
# On AWS VM
docker exec vxlan-processor vppctl show trace
docker exec security-processor vppctl show trace

# On GCP VM
docker exec destination vppctl show trace
```

**Check interface statistics:**
```bash
# On AWS VM
docker exec vxlan-processor vppctl show interface | grep -E "rx packets|tx packets"
docker exec security-processor vppctl show interface | grep -E "rx packets|tx packets"

# On GCP VM
docker exec destination vppctl show interface | grep -E "rx packets|tx packets"
```

## Step 8: Verify Packet Flow

### End-to-End Packet Flow Verification:
```bash
# Check VPP runtime performance
docker exec vxlan-processor vppctl show runtime
docker exec security-processor vppctl show runtime  
docker exec destination vppctl show runtime

# Monitor interface counters
watch -n 5 'docker exec vxlan-processor vppctl show interface | head -10'
```

### Expected Traffic Flow:
1. **AWS VXLAN-PROCESSOR**: Receives packets on ens5 → VXLAN decapsulation → BVI L2→L3
2. **AWS SECURITY-PROCESSOR**: NAT44 translation → IPsec encryption → IP fragmentation
3. **Cross-Cloud VPN**: Encrypted packet transmission AWS → GCP
4. **GCP DESTINATION**: IPsec decryption → packet reassembly → TAP interface delivery

## Management Commands

### Container Management:
```bash
# Check status
python3 src/main.py status

# Debug containers
python3 src/main.py debug vxlan-processor "show interface"
python3 src/main.py debug security-processor "show nat44 sessions"
python3 src/main.py debug destination "show interface tap0"

# Cleanup (if needed)
python3 src/main.py cleanup
```

### VPP Debugging:
```bash
# Direct VPP access
docker exec -it vxlan-processor vppctl
docker exec -it security-processor vppctl  
docker exec -it destination vppctl

# Common VPP commands
show interface
show runtime
show errors
show trace
```

### Performance Monitoring:
```bash
# Monitor packet processing
docker exec <container> vppctl show interface | grep -E "drops|errors"

# Monitor VPP performance
docker exec <container> vppctl show runtime | grep -E "calls|vectors"

# Check memory usage
docker exec <container> vppctl show memory
```

## Troubleshooting

### Container Issues:
```bash
# Check container logs
docker logs vxlan-processor
docker logs security-processor
docker logs destination

# Check container health
docker inspect <container-name>
```

### VPP Issues:
```bash
# Check VPP logs
docker exec <container> cat /tmp/vpp.log

# Restart VPP if needed
docker exec <container> pkill vpp
docker restart <container>
```

### Network Issues:
```bash
# Check Docker networks
docker network ls
docker network inspect <network-name>

# Check host networking
ip addr show
ip route show
```

### Cross-Cloud Connectivity Issues:
```bash
# Test basic connectivity
ping 192.168.200.1  # From GCP to AWS
ping 192.168.200.2  # From AWS to GCP

# Check VPN status (check with your VPN solution)
# Verify routing tables include cross-cloud networks
ip route | grep 192.168.200
```

## Performance Expectations

**After Successful Deployment:**
- VPP containers running with no errors
- Cross-cloud connectivity established  
- Packet processing through VXLAN → NAT44 → IPsec → TAP
- Sub-millisecond per-container latency
- 10-100x performance improvement over kernel networking
- Secure cross-cloud encrypted communication

## Emergency Recovery

**Complete cleanup and redeploy:**
```bash
# On both VMs
python3 src/main.py cleanup
sudo ./deploy_aws_multicloud.sh    # AWS
sudo ./deploy_gcp_multicloud.sh    # GCP
```

**Network state recovery:**
```bash
# Check backup locations (created during deployment)
ls /tmp/*_vpp_backup_*
```

This guide focuses purely on network deployment and packet delivery across VPN connections, assuming VMs and basic infrastructure are already provisioned.