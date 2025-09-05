# VPP Multi-Container Chain Production Deployment Guide

This guide provides comprehensive instructions for deploying the VPP multi-container chain solution in production AWS and GCP environments.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [AWS Deployment](#aws-deployment)
4. [GCP Deployment](#gcp-deployment)
5. [Cross-Cloud Connectivity](#cross-cloud-connectivity)
6. [Security Configuration](#security-configuration)
7. [Monitoring & Logging](#monitoring--logging)
8. [Automation & CI/CD](#automation--cicd)
9. [Troubleshooting](#troubleshooting)
10. [Performance Tuning](#performance-tuning)

## Architecture Overview

### Production Use Cases

This VPP multi-container chain is designed for:

- **Multi-Cloud Connectivity**: Secure tunneling between AWS and GCP
- **Network Function Virtualization (NFV)**: Service chaining for enterprise networks
- **Service Mesh Data Plane**: High-performance packet processing for microservices
- **Edge Computing**: Low-latency packet processing at network edges
- **Security Gateway**: Combined NAT + IPsec processing for enterprise traffic

### Component Architecture

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   INGRESS   │───▶│   VXLAN     │───▶│    NAT44    │───▶│   IPSEC     │───▶│ FRAGMENT    │───▶ [Cloud Endpoint]
│   Gateway   │    │ Decap VNI   │    │ Translation │    │ AES-GCM-128 │    │  MTU 1400   │
│  (AWS/GCP)  │    │    100      │    │ 10.10.10.10 │    │ Encryption  │    │ Fragments   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

## Prerequisites

### General Requirements

- Ubuntu 20.04 LTS or 22.04 LTS
- Minimum 8GB RAM, 4 vCPUs
- 50GB+ storage for containers and logs
- Root/sudo access
- Docker 20.10+ and docker-compose
- Python 3.8+

### Cloud-Specific Requirements

**AWS**:
- VPC with appropriate subnets
- Security Groups allowing required ports
- IAM roles for instance management
- Elastic IPs for stable addressing

**GCP**:
- VPC network with firewall rules
- Compute Engine instances with required scopes
- Cloud NAT or external IPs
- Service accounts with appropriate permissions

## AWS Deployment

### 1. Infrastructure Setup

#### Create VPC and Subnets

```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=vpp-chain-vpc}]'

# Create subnets
aws ec2 create-subnet --vpc-id vpc-xxxxxxxx --cidr-block 10.0.1.0/24 --availability-zone us-west-2a
aws ec2 create-subnet --vpc-id vpc-xxxxxxxx --cidr-block 10.0.2.0/24 --availability-zone us-west-2b

# Create Internet Gateway
aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=vpp-chain-igw}]'
aws ec2 attach-internet-gateway --vpc-id vpc-xxxxxxxx --internet-gateway-id igw-xxxxxxxx
```

#### Security Groups

```bash
# Create security group
aws ec2 create-security-group --group-name vpp-chain-sg --description "VPP Chain Security Group" --vpc-id vpc-xxxxxxxx

# Allow SSH
aws ec2 authorize-security-group-ingress --group-id sg-xxxxxxxx --protocol tcp --port 22 --cidr 0.0.0.0/0

# Allow VXLAN (UDP 4789)
aws ec2 authorize-security-group-ingress --group-id sg-xxxxxxxx --protocol udp --port 4789 --cidr 10.0.0.0/16

# Allow IPsec (ESP - protocol 50)
aws ec2 authorize-security-group-ingress --group-id sg-xxxxxxxx --protocol 50 --cidr 0.0.0.0/0

# Allow custom UDP ports for testing
aws ec2 authorize-security-group-ingress --group-id sg-xxxxxxxx --protocol udp --port 2055 --cidr 10.0.0.0/16
```

### 2. EC2 Instance Launch

#### Launch Template

```json
{
  "LaunchTemplateName": "vpp-chain-template",
  "LaunchTemplateData": {
    "ImageId": "ami-0c02fb55956c7d316",
    "InstanceType": "c5.2xlarge",
    "SecurityGroupIds": ["sg-xxxxxxxx"],
    "IamInstanceProfile": {
      "Name": "vpp-chain-instance-profile"
    },
    "UserData": "base64-encoded-user-data-script",
    "TagSpecifications": [
      {
        "ResourceType": "instance",
        "Tags": [
          {
            "Key": "Name",
            "Value": "vpp-chain-node"
          },
          {
            "Key": "Environment",
            "Value": "production"
          }
        ]
      }
    ]
  }
}
```

#### User Data Script

```bash
#!/bin/bash
set -e

# Update system
apt-get update -y
apt-get upgrade -y

# Install required packages
apt-get install -y docker.io docker-compose python3-pip python3-scapy git

# Enable and start Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install additional Python packages
pip3 install docker-compose scapy

# Clone VPP chain repository
cd /opt
git clone <your-repo-url> vpp-chain
cd vpp-chain
chown -R ubuntu:ubuntu /opt/vpp-chain

# Configure AWS mode in config
sed -i 's/"default_mode": "gcp"/"default_mode": "aws"/' config.json

# Setup logging directory
mkdir -p /var/log/vpp-chain
chown ubuntu:ubuntu /var/log/vpp-chain

# Create systemd service for VPP chain
cat > /etc/systemd/system/vpp-chain.service << 'EOF'
[Unit]
Description=VPP Multi-Container Chain
After=docker.service
Requires=docker.service

[Service]
Type=forking
User=ubuntu
WorkingDirectory=/opt/vpp-chain
ExecStart=/usr/bin/python3 src/main.py setup
ExecStop=/usr/bin/python3 src/main.py cleanup
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpp-chain.service

# Reboot to ensure all changes take effect
reboot
```

### 3. Application Deployment

```bash
# SSH to the instance
ssh -i your-key.pem ubuntu@<instance-ip>

# Navigate to VPP chain directory
cd /opt/vpp-chain

# Setup the VPP chain
sudo python3 src/main.py setup

# Verify deployment
sudo python3 src/main.py status

# Run connectivity tests
sudo python3 src/main.py test --type connectivity
```

## GCP Deployment

### 1. Infrastructure Setup

#### Create VPC Network

```bash
# Create VPC
gcloud compute networks create vpp-chain-network --subnet-mode regional

# Create subnet
gcloud compute networks subnets create vpp-chain-subnet \
    --network vpp-chain-network \
    --range 10.0.0.0/16 \
    --region us-central1

# Create firewall rules
gcloud compute firewall-rules create vpp-chain-allow-ssh \
    --network vpp-chain-network \
    --allow tcp:22 \
    --source-ranges 0.0.0.0/0

gcloud compute firewall-rules create vpp-chain-allow-vxlan \
    --network vpp-chain-network \
    --allow udp:4789 \
    --source-ranges 10.0.0.0/16

gcloud compute firewall-rules create vpp-chain-allow-ipsec \
    --network vpp-chain-network \
    --allow esp \
    --source-ranges 0.0.0.0/0

gcloud compute firewall-rules create vpp-chain-allow-internal \
    --network vpp-chain-network \
    --allow tcp,udp,icmp \
    --source-ranges 10.0.0.0/16
```

### 2. Compute Engine Instance

#### Create Instance Template

```bash
# Create instance template
gcloud compute instance-templates create vpp-chain-template \
    --machine-type c2-standard-4 \
    --network-interface network=vpp-chain-network,subnet=vpp-chain-subnet \
    --image-family ubuntu-2004-lts \
    --image-project ubuntu-os-cloud \
    --boot-disk-size 50GB \
    --boot-disk-type pd-ssd \
    --metadata-from-file startup-script=startup-script.sh \
    --tags vpp-chain-node \
    --service-account <your-service-account>@<project>.iam.gserviceaccount.com \
    --scopes compute-rw,storage-ro,logging-write,monitoring-write
```

#### Startup Script (startup-script.sh)

```bash
#!/bin/bash
set -e

# Update system
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
usermod -aG docker $(logname)

# Install Python dependencies
apt-get install -y python3-pip python3-scapy git
pip3 install docker-compose

# Install Google Cloud Ops Agent
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install

# Clone repository
cd /opt
git clone <your-repo-url> vpp-chain
cd vpp-chain
chown -R $(logname):$(logname) /opt/vpp-chain

# Configure GCP mode (default)
echo "Using GCP configuration mode"

# Setup logging
mkdir -p /var/log/vpp-chain
chown $(logname):$(logname) /var/log/vpp-chain

# Create service
cat > /etc/systemd/system/vpp-chain.service << 'EOF'
[Unit]
Description=VPP Multi-Container Chain
After=docker.service
Requires=docker.service

[Service]
Type=forking
User=$(logname)
WorkingDirectory=/opt/vpp-chain
ExecStart=/usr/bin/python3 src/main.py setup
ExecStop=/usr/bin/python3 src/main.py cleanup
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpp-chain.service

# Setup firewall (if using OS-level firewall)
ufw allow 22/tcp
ufw allow 4789/udp
ufw allow 2055/udp
ufw --force enable

reboot
```

### 3. Managed Instance Group (Optional)

```bash
# Create managed instance group for high availability
gcloud compute instance-groups managed create vpp-chain-group \
    --template vpp-chain-template \
    --size 2 \
    --zone us-central1-a

# Setup auto-scaling
gcloud compute instance-groups managed set-autoscaling vpp-chain-group \
    --max-num-replicas 5 \
    --min-num-replicas 2 \
    --target-cpu-utilization 0.8 \
    --zone us-central1-a

# Create health check
gcloud compute health-checks create tcp vpp-chain-health-check \
    --port 22 \
    --check-interval 30s \
    --timeout 10s \
    --unhealthy-threshold 3 \
    --healthy-threshold 2
```

## Cross-Cloud Connectivity

### 1. VPN Connection Setup

#### AWS Side (VPN Gateway)

```bash
# Create VPN Gateway
aws ec2 create-vpn-gateway --type ipsec.1 --amazon-side-asn 65000

# Attach to VPC
aws ec2 attach-vpn-gateway --vpn-gateway-id vgw-xxxxxxxx --vpc-id vpc-xxxxxxxx

# Create Customer Gateway (GCP side)
aws ec2 create-customer-gateway \
    --type ipsec.1 \
    --public-ip <gcp-external-ip> \
    --bgp-asn 65001 \
    --tag-specifications 'ResourceType=customer-gateway,Tags=[{Key=Name,Value=gcp-gateway}]'

# Create VPN Connection
aws ec2 create-vpn-connection \
    --type ipsec.1 \
    --customer-gateway-id cgw-xxxxxxxx \
    --vpn-gateway-id vgw-xxxxxxxx \
    --options StaticRoutesOnly=true
```

#### GCP Side (Cloud VPN)

```bash
# Create VPN Gateway
gcloud compute vpn-gateways create gcp-vpn-gateway \
    --network vpp-chain-network \
    --region us-central1

# Reserve external IP
gcloud compute addresses create gcp-vpn-ip --region us-central1

# Create VPN tunnel
gcloud compute vpn-tunnels create aws-tunnel \
    --peer-address <aws-vpn-endpoint> \
    --shared-secret <pre-shared-key> \
    --target-vpn-gateway gcp-vpn-gateway \
    --region us-central1 \
    --local-traffic-selector 10.0.0.0/16 \
    --remote-traffic-selector 10.0.0.0/16

# Create forwarding rules
gcloud compute forwarding-rules create aws-tunnel-esp \
    --address gcp-vpn-ip \
    --ip-protocol ESP \
    --target-vpn-gateway gcp-vpn-gateway \
    --region us-central1

gcloud compute forwarding-rules create aws-tunnel-udp500 \
    --address gcp-vpn-ip \
    --ip-protocol UDP \
    --ports 500 \
    --target-vpn-gateway gcp-vpn-gateway \
    --region us-central1

gcloud compute forwarding-rules create aws-tunnel-udp4500 \
    --address gcp-vpn-ip \
    --ip-protocol UDP \
    --ports 4500 \
    --target-vpn-gateway gcp-vpn-gateway \
    --region us-central1
```

### 2. VPP Chain Cross-Cloud Configuration

#### Update Configuration for Cross-Cloud

```json
{
  "cross_cloud_mode": true,
  "aws_endpoint": {
    "public_ip": "<aws-instance-external-ip>",
    "private_ip": "10.0.1.10",
    "vpc_cidr": "10.0.0.0/16"
  },
  "gcp_endpoint": {
    "public_ip": "<gcp-instance-external-ip>", 
    "private_ip": "10.0.1.20",
    "vpc_cidr": "10.0.0.0/16"
  },
  "ipsec_config": {
    "pre_shared_key": "your-secure-psk",
    "encryption": "aes-gcm-256",
    "peer_aws_ip": "<aws-external-ip>",
    "peer_gcp_ip": "<gcp-external-ip>"
  }
}
```

#### Deploy Cross-Cloud Test Traffic

```python
# cross_cloud_test.py
import socket
from scapy.all import *
import time

def generate_cross_cloud_traffic(aws_ip, gcp_ip):
    """Generate test traffic between AWS and GCP endpoints"""
    
    # Create large test packets to trigger fragmentation
    inner_payload = "X" * 7000  # 7KB payload
    inner_packet = IP(src="10.10.10.5", dst="10.10.10.10")/UDP(sport=1234, dport=2055)/inner_payload
    
    # Encapsulate in VXLAN
    vxlan_packet = VXLAN(vni=100)/inner_packet
    outer_packet = IP(src=aws_ip, dst=gcp_ip)/UDP(sport=12345, dport=4789)/vxlan_packet
    
    print(f"Sending cross-cloud traffic: {aws_ip} -> {gcp_ip}")
    send(outer_packet, count=10, inter=0.5)
    
    print("Cross-cloud traffic test completed")

if __name__ == "__main__":
    aws_ip = "10.0.1.10"    # AWS VPP chain endpoint
    gcp_ip = "10.0.1.20"    # GCP VPP chain endpoint
    
    generate_cross_cloud_traffic(aws_ip, gcp_ip)
```

## Security Configuration

### 1. Network Security

#### IPsec Configuration Hardening

```bash
# Update IPsec configuration for production
sudo python3 -c "
import json
with open('config.json', 'r') as f:
    config = json.load(f)

# Production IPsec settings
config['ipsec_production'] = {
    'encryption_algorithm': 'aes-gcm-256',
    'integrity_algorithm': 'sha384',
    'dh_group': '19',  # ECC 256-bit
    'pfs_enabled': True,
    'replay_window': 64,
    'lifetime_seconds': 3600,
    'lifetime_bytes': '100MB'
}

with open('config.json', 'w') as f:
    json.dump(config, f, indent=2)
"
```

#### Container Security

```yaml
# docker-compose.override.yml for production
version: '3.8'
services:
  chain-ingress:
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=64m
    cap_drop:
      - ALL
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    
  chain-vxlan:
    security_opt:
      - no-new-privileges:true
    read_only: true
    cap_drop:
      - ALL
    cap_add:
      - NET_ADMIN
    
  # Apply similar security settings to other containers
```

### 2. Access Control

#### IAM Roles (AWS)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeNetworkInterfaces",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

#### Service Account (GCP)

```bash
# Create service account
gcloud iam service-accounts create vpp-chain-sa \
    --display-name "VPP Chain Service Account"

# Grant necessary permissions
gcloud projects add-iam-policy-binding <project-id> \
    --member serviceAccount:vpp-chain-sa@<project-id>.iam.gserviceaccount.com \
    --role roles/compute.instanceAdmin.v1

gcloud projects add-iam-policy-binding <project-id> \
    --member serviceAccount:vpp-chain-sa@<project-id>.iam.gserviceaccount.com \
    --role roles/logging.logWriter

gcloud projects add-iam-policy-binding <project-id> \
    --member serviceAccount:vpp-chain-sa@<project-id>.iam.gserviceaccount.com \
    --role roles/monitoring.metricWriter
```

### 3. Certificate Management

```bash
# Generate production certificates for IPsec
openssl genrsa -out /etc/vpp-chain/private-key.pem 4096
openssl req -new -x509 -key /etc/vpp-chain/private-key.pem \
    -out /etc/vpp-chain/certificate.pem \
    -days 365 \
    -subj "/C=US/ST=CA/L=SF/O=YourOrg/CN=vpp-chain.yourdomain.com"

# Secure the certificates
chmod 400 /etc/vpp-chain/private-key.pem
chmod 444 /etc/vpp-chain/certificate.pem
chown root:root /etc/vpp-chain/*.pem
```

## Monitoring & Logging

### 1. Metrics Collection

#### CloudWatch (AWS)

```bash
# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Configuration file
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "metrics": {
    "namespace": "VPP/Chain",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait"
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/vpp-chain/*.log",
            "log_group_name": "vpp-chain-logs",
            "log_stream_name": "{instance_id}-vpp-chain"
          }
        ]
      }
    }
  }
}
EOF

# Start agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent
```

#### Cloud Monitoring (GCP)

```yaml
# monitoring-config.yaml
resources:
- name: vpp-chain-dashboard
  type: gcp-types/monitoring-v1:projects.dashboards
  properties:
    displayName: "VPP Chain Monitoring"
    mosaicLayout:
      tiles:
      - width: 6
        height: 4
        widget:
          title: "Container CPU Usage"
          xyChart:
            dataSets:
            - timeSeriesQuery:
                timeSeriesFilter:
                  filter: 'resource.type="gce_instance" metric.type="compute.googleapis.com/instance/cpu/utilization"'
                  aggregation:
                    alignmentPeriod: "60s"
                    perSeriesAligner: "ALIGN_MEAN"
```

### 2. Log Management

#### Structured Logging Setup

```python
# production_logger.py
import logging
import json
import sys
from datetime import datetime

class VPPChainLogger:
    def __init__(self, service_name):
        self.service_name = service_name
        self.logger = logging.getLogger(service_name)
        
        # Production log format
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        
        # File handler
        file_handler = logging.FileHandler(f'/var/log/vpp-chain/{service_name}.log')
        file_handler.setFormatter(formatter)
        
        # Console handler for JSON logs
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(self.JSONFormatter())
        
        self.logger.addHandler(file_handler)
        self.logger.addHandler(console_handler)
        self.logger.setLevel(logging.INFO)
    
    class JSONFormatter(logging.Formatter):
        def format(self, record):
            log_entry = {
                'timestamp': datetime.utcnow().isoformat(),
                'level': record.levelname,
                'service': record.name,
                'message': record.getMessage(),
                'module': record.module,
                'function': record.funcName,
                'line': record.lineno
            }
            return json.dumps(log_entry)
    
    def info(self, message, **kwargs):
        self.logger.info(message, extra=kwargs)
    
    def error(self, message, **kwargs):
        self.logger.error(message, extra=kwargs)
    
    def warning(self, message, **kwargs):
        self.logger.warning(message, extra=kwargs)
```

### 3. Health Checks

```python
# health_check.py
import requests
import docker
import subprocess
import json
import time

class VPPChainHealthCheck:
    def __init__(self):
        self.client = docker.from_env()
        self.containers = [
            'chain-ingress', 'chain-vxlan', 'chain-nat', 
            'chain-ipsec', 'chain-fragment', 'chain-gcp'
        ]
    
    def check_container_health(self):
        """Check if all VPP chain containers are running"""
        health_status = {}
        
        for container_name in self.containers:
            try:
                container = self.client.containers.get(container_name)
                health_status[container_name] = {
                    'status': container.status,
                    'health': 'healthy' if container.status == 'running' else 'unhealthy'
                }
            except docker.errors.NotFound:
                health_status[container_name] = {
                    'status': 'not_found',
                    'health': 'unhealthy'
                }
        
        return health_status
    
    def check_vpp_responsiveness(self):
        """Check if VPP is responsive in each container"""
        vpp_status = {}
        
        for container_name in self.containers:
            try:
                result = subprocess.run([
                    'docker', 'exec', container_name, 'vppctl', 'show', 'version'
                ], capture_output=True, text=True, timeout=10)
                
                vpp_status[container_name] = {
                    'responsive': result.returncode == 0,
                    'output': result.stdout.strip() if result.returncode == 0 else result.stderr.strip()
                }
            except subprocess.TimeoutExpired:
                vpp_status[container_name] = {
                    'responsive': False,
                    'output': 'timeout'
                }
            except Exception as e:
                vpp_status[container_name] = {
                    'responsive': False,
                    'output': str(e)
                }
        
        return vpp_status
    
    def get_interface_statistics(self):
        """Get VPP interface statistics from all containers"""
        stats = {}
        
        for container_name in self.containers:
            try:
                result = subprocess.run([
                    'docker', 'exec', container_name, 'vppctl', 'show', 'interface'
                ], capture_output=True, text=True, timeout=10)
                
                if result.returncode == 0:
                    stats[container_name] = self.parse_interface_stats(result.stdout)
                else:
                    stats[container_name] = {'error': result.stderr}
                    
            except Exception as e:
                stats[container_name] = {'error': str(e)}
        
        return stats
    
    def parse_interface_stats(self, output):
        """Parse VPP interface statistics output"""
        interfaces = {}
        current_interface = None
        
        for line in output.split('\n'):
            if line.strip().startswith(('host-', 'vxlan_', 'ipip')):
                parts = line.split()
                current_interface = parts[0]
                interfaces[current_interface] = {}
            elif current_interface and 'packets' in line:
                if 'rx packets' in line:
                    interfaces[current_interface]['rx_packets'] = int(line.split()[-1])
                elif 'tx packets' in line:
                    interfaces[current_interface]['tx_packets'] = int(line.split()[-1])
                elif 'drops' in line:
                    interfaces[current_interface]['drops'] = int(line.split()[-1])
        
        return interfaces
    
    def run_health_check(self):
        """Run complete health check and return results"""
        health_report = {
            'timestamp': time.time(),
            'containers': self.check_container_health(),
            'vpp': self.check_vpp_responsiveness(),
            'interfaces': self.get_interface_statistics()
        }
        
        # Calculate overall health
        container_health = all(
            status['health'] == 'healthy' 
            for status in health_report['containers'].values()
        )
        vpp_health = all(
            status['responsive'] 
            for status in health_report['vpp'].values()
        )
        
        health_report['overall_health'] = 'healthy' if (container_health and vpp_health) else 'unhealthy'
        
        return health_report

if __name__ == "__main__":
    checker = VPPChainHealthCheck()
    report = checker.run_health_check()
    print(json.dumps(report, indent=2))
```

This comprehensive production deployment guide covers AWS and GCP deployments with proper security, monitoring, and cross-cloud connectivity. The guide includes infrastructure setup, automation scripts, security hardening, and operational monitoring to ensure a robust production deployment.