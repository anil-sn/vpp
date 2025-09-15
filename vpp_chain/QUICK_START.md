# Quick Start Commands

## Prerequisites
- AWS VM with ens5/ens6 interfaces
- GCP VM with network interfaces  
- VPN connection established between clouds
- Root access on both VMs

## Step-by-Step Deployment Commands

### 1. Setup Repository (Both VMs)

**AWS VM:**
```bash
ssh user@aws-vm-ip
sudo su -
cd /opt && git clone <repo-url> vpp_chain && cd vpp_chain
```

**GCP VM:**
```bash
ssh user@gcp-vm-ip  
sudo su -
cd /opt && git clone <repo-url> vpp_chain && cd vpp_chain
```

### 2. Generate Configuration Files (Run Once)

```bash
cd /opt/vpp_chain
python3 configure_multicloud_deployment.py
```

**Input Required:**
- AWS Region: `us-west-2`
- GCP Region: `us-central1` 
- Cross-cloud Network: `192.168.200.0/24`
- VPN details and IP assignments

**Files Generated:**
- `production_aws_config.json`
- `production_gcp_config.json`

### 3. Deploy AWS Side

```bash
cd /opt/vpp_chain
sudo ./deploy_aws_multicloud.sh
```

### 4. Deploy GCP Side

```bash
cd /opt/vpp_chain
sudo ./deploy_gcp_multicloud.sh
```

### 5. Validate Deployment

**AWS VM:**
```bash
python3 cross_cloud_diagnostics.py
docker ps --filter "name=vxlan-processor" --filter "name=security-processor"
```

**GCP VM:**
```bash
python3 cross_cloud_diagnostics.py
docker ps --filter "name=destination"
```

### 6. Test Traffic Flow

**Enable tracing:**
```bash
# AWS
docker exec vxlan-processor vppctl clear trace && docker exec vxlan-processor vppctl trace add af-packet-input 10
docker exec security-processor vppctl clear trace && docker exec security-processor vppctl trace add af-packet-input 10

# GCP
docker exec destination vppctl clear trace && docker exec destination vppctl trace add af-packet-input 10
```

**Check results:**
```bash
# AWS
docker exec vxlan-processor vppctl show trace
docker exec security-processor vppctl show trace

# GCP  
docker exec destination vppctl show trace
```

## Verification Commands

**Container Status:**
```bash
docker ps | grep -E "vxlan|security|destination"
```

**VPP Status:**
```bash
docker exec <container> vppctl show interface
docker exec <container> vppctl show runtime
```

**Cross-Cloud Connectivity:**
```bash
# From AWS to GCP
docker exec security-processor ping -c 3 192.168.200.2

# From GCP to AWS
docker exec destination ping -c 3 192.168.200.1
```

## Troubleshooting

**Container Issues:**
```bash
docker logs <container-name>
docker restart <container-name>
```

**Complete Reset:**
```bash
python3 src/main.py cleanup
sudo ./deploy_aws_multicloud.sh  # or deploy_gcp_multicloud.sh
```

**Expected Result:** 
- Packets flow: ens5 → VPP chain → VPN → GCP → TAP interface
- Sub-millisecond processing latency
- Cross-cloud encrypted communication