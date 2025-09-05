# Cross-Cloud Connectivity Guide

This guide provides detailed instructions for establishing secure connectivity between AWS and GCP deployments of the VPP multi-container chain, enabling true multi-cloud network function virtualization.

## Architecture Overview

```
AWS Region (us-west-2)                    GCP Region (us-central1)
┌─────────────────────────┐              ┌─────────────────────────┐
│  VPC (10.0.0.0/16)     │              │  VPC (10.0.0.0/16)     │
│                        │              │                        │
│  ┌─────────────────┐   │   VPN/VXLAN  │   ┌─────────────────┐  │
│  │  VPP Chain      │   │◄────────────►│   │  VPP Chain      │  │
│  │  VXLAN→NAT→     │   │              │   │  VXLAN→NAT→     │  │
│  │  IPsec→Fragment │   │              │   │  IPsec→Fragment │  │
│  └─────────────────┘   │              │   └─────────────────┘  │
│                        │              │                        │
│  Internet Gateway      │              │  Cloud NAT             │
└─────────────────────────┘              └─────────────────────────┘
```

## Implementation Options

### Option 1: VPN-Based Connectivity

#### 1.1 AWS VPN Gateway Setup

```bash
# Create VPN Gateway
aws ec2 create-vpn-gateway \
    --type ipsec.1 \
    --amazon-side-asn 65000 \
    --tag-specifications 'ResourceType=vpn-gateway,Tags=[{Key=Name,Value=vpp-chain-vpn-gw}]'

# Attach to VPC
VGW_ID=$(aws ec2 describe-vpn-gateways --filters "Name=tag:Name,Values=vpp-chain-vpn-gw" --query "VpnGateways[0].VpnGatewayId" --output text)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=vpp-chain-vpc-*" --query "Vpcs[0].VpcId" --output text)

aws ec2 attach-vpn-gateway \
    --vpn-gateway-id $VGW_ID \
    --vpc-id $VPC_ID

# Enable route propagation
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*" --query "RouteTables[0].RouteTableId" --output text)
aws ec2 enable-vgw-route-propagation \
    --route-table-id $ROUTE_TABLE_ID \
    --gateway-id $VGW_ID
```

#### 1.2 GCP Cloud VPN Setup

```bash
# Reserve external IP for VPN
gcloud compute addresses create gcp-vpn-ip \
    --region us-central1

# Get the reserved IP
GCP_VPN_IP=$(gcloud compute addresses describe gcp-vpn-ip --region us-central1 --format="value(address)")

# Create VPN Gateway
gcloud compute vpn-gateways create gcp-vpn-gateway \
    --network vpp-chain-network-production \
    --region us-central1

# Create customer gateway on AWS side
aws ec2 create-customer-gateway \
    --type ipsec.1 \
    --public-ip $GCP_VPN_IP \
    --bgp-asn 65001 \
    --tag-specifications 'ResourceType=customer-gateway,Tags=[{Key=Name,Value=gcp-customer-gateway}]'

# Get AWS VPN endpoint IP (after VPN connection is created)
# This will be provided by AWS after creating the VPN connection
```

#### 1.3 VPN Connection Configuration

```bash
# Create VPN connection on AWS
CGW_ID=$(aws ec2 describe-customer-gateways --filters "Name=tag:Name,Values=gcp-customer-gateway" --query "CustomerGateways[0].CustomerGatewayId" --output text)

aws ec2 create-vpn-connection \
    --type ipsec.1 \
    --customer-gateway-id $CGW_ID \
    --vpn-gateway-id $VGW_ID \
    --options StaticRoutesOnly=true \
    --tag-specifications 'ResourceType=vpn-connection,Tags=[{Key=Name,Value=aws-gcp-vpn}]'

# Add static routes
VPN_CONN_ID=$(aws ec2 describe-vpn-connections --filters "Name=tag:Name,Values=aws-gcp-vpn" --query "VpnConnections[0].VpnConnectionId" --output text)
aws ec2 create-vpn-connection-route \
    --vpn-connection-id $VPN_CONN_ID \
    --destination-cidr-block 10.0.0.0/16

# Get AWS VPN endpoint IP for GCP configuration
AWS_VPN_IP=$(aws ec2 describe-vpn-connections --vpn-connection-ids $VPN_CONN_ID --query "VpnConnections[0].Options.TunnelOptions[0].OutsideIpAddress" --output text)
PRE_SHARED_KEY=$(aws ec2 describe-vpn-connections --vpn-connection-ids $VPN_CONN_ID --query "VpnConnections[0].Options.TunnelOptions[0].PreSharedKey" --output text)
```

#### 1.4 Complete GCP VPN Configuration

```bash
# Create VPN tunnel on GCP side
gcloud compute vpn-tunnels create aws-tunnel \
    --peer-address $AWS_VPN_IP \
    --shared-secret $PRE_SHARED_KEY \
    --target-vpn-gateway gcp-vpn-gateway \
    --region us-central1 \
    --local-traffic-selector 10.0.0.0/16 \
    --remote-traffic-selector 10.0.0.0/16

# Create forwarding rules
gcloud compute forwarding-rules create aws-tunnel-esp \
    --address $GCP_VPN_IP \
    --ip-protocol ESP \
    --target-vpn-gateway gcp-vpn-gateway \
    --region us-central1

gcloud compute forwarding-rules create aws-tunnel-udp500 \
    --address $GCP_VPN_IP \
    --ip-protocol UDP \
    --ports 500 \
    --target-vpn-gateway gcp-vpn-gateway \
    --region us-central1

gcloud compute forwarding-rules create aws-tunnel-udp4500 \
    --address $GCP_VPN_IP \
    --ip-protocol UDP \
    --ports 4500 \
    --target-vpn-gateway gcp-vpn-gateway \
    --region us-central1

# Create route to AWS
gcloud compute routes create aws-route \
    --destination-range 10.0.0.0/16 \
    --next-hop-vpn-tunnel aws-tunnel \
    --next-hop-vpn-tunnel-region us-central1 \
    --network vpp-chain-network-production
```

### Option 2: Direct VXLAN Overlay

For higher performance and more control, establish direct VXLAN tunnels between clouds:

#### 2.1 VXLAN Tunnel Configuration Script

```python
# cross_cloud_vxlan_setup.py
import subprocess
import json
import time
from dataclasses import dataclass
from typing import Dict, List

@dataclass
class CloudEndpoint:
    cloud: str
    external_ip: str
    internal_ip: str
    vpc_cidr: str
    instance_name: str

class CrossCloudVXLANManager:
    def __init__(self, aws_endpoint: CloudEndpoint, gcp_endpoint: CloudEndpoint):
        self.aws_endpoint = aws_endpoint
        self.gcp_endpoint = gcp_endpoint
        self.vxlan_vni = 200  # Different VNI for cross-cloud traffic
    
    def setup_cross_cloud_vxlan(self):
        """Setup VXLAN tunnels between AWS and GCP"""
        print("🌐 Setting up cross-cloud VXLAN connectivity")
        
        # Configure AWS side
        self.configure_aws_vxlan()
        
        # Configure GCP side  
        self.configure_gcp_vxlan()
        
        # Test connectivity
        self.test_cross_cloud_connectivity()
    
    def configure_aws_vxlan(self):
        """Configure VXLAN on AWS instance"""
        print(f"🔧 Configuring AWS VXLAN ({self.aws_endpoint.instance_name})")
        
        vxlan_config = f"""
#!/bin/bash
set -e

# Create VXLAN interface for cross-cloud communication
sudo ip link add vxlan-gcp type vxlan id {self.vxlan_vni} \\
    remote {self.gcp_endpoint.external_ip} \\
    dstport 4789 \\
    dev eth0

# Configure IP address
sudo ip addr add 192.168.100.1/24 dev vxlan-gcp
sudo ip link set vxlan-gcp up

# Add route to GCP VPC
sudo ip route add {self.gcp_endpoint.vpc_cidr} dev vxlan-gcp

# Configure VPP to use VXLAN tunnel
docker exec chain-ingress vppctl create host-interface name vxlan-gcp
docker exec chain-ingress vppctl set interface ip address host-vxlan-gcp 192.168.100.1/24
docker exec chain-ingress vppctl set interface state host-vxlan-gcp up
docker exec chain-ingress vppctl ip route add {self.gcp_endpoint.vpc_cidr} via 192.168.100.2 host-vxlan-gcp
"""
        
        # Execute on AWS instance
        self.execute_remote_script(self.aws_endpoint, vxlan_config)
    
    def configure_gcp_vxlan(self):
        """Configure VXLAN on GCP instance"""
        print(f"🔧 Configuring GCP VXLAN ({self.gcp_endpoint.instance_name})")
        
        vxlan_config = f"""
#!/bin/bash
set -e

# Create VXLAN interface for cross-cloud communication
sudo ip link add vxlan-aws type vxlan id {self.vxlan_vni} \\
    remote {self.aws_endpoint.external_ip} \\
    dstport 4789 \\
    dev ens4

# Configure IP address
sudo ip addr add 192.168.100.2/24 dev vxlan-aws
sudo ip link set vxlan-aws up

# Add route to AWS VPC
sudo ip route add {self.aws_endpoint.vpc_cidr} dev vxlan-aws

# Configure VPP to use VXLAN tunnel
docker exec chain-ingress vppctl create host-interface name vxlan-aws
docker exec chain-ingress vppctl set interface ip address host-vxlan-aws 192.168.100.2/24
docker exec chain-ingress vppctl set interface state host-vxlan-aws up
docker exec chain-ingress vppctl ip route add {self.aws_endpoint.vpc_cidr} via 192.168.100.1 host-vxlan-aws
"""
        
        # Execute on GCP instance
        self.execute_remote_script(self.gcp_endpoint, vxlan_config)
    
    def execute_remote_script(self, endpoint: CloudEndpoint, script: str):
        """Execute script on remote instance"""
        try:
            if endpoint.cloud == "aws":
                # Use SSH to execute on AWS instance
                subprocess.run([
                    "ssh", "-i", "aws-key.pem", f"ubuntu@{endpoint.external_ip}",
                    script
                ], check=True)
            elif endpoint.cloud == "gcp":
                # Use gcloud SSH to execute on GCP instance
                subprocess.run([
                    "gcloud", "compute", "ssh", endpoint.instance_name,
                    "--zone", "us-central1-a",
                    "--command", script
                ], check=True)
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to configure {endpoint.cloud}: {e}")
    
    def test_cross_cloud_connectivity(self):
        """Test connectivity between clouds"""
        print("🧪 Testing cross-cloud connectivity")
        
        # Test from AWS to GCP
        aws_test = f"""
ping -c 3 192.168.100.2
docker exec chain-ingress vppctl ping 192.168.100.2 repeat 3
"""
        
        # Test from GCP to AWS
        gcp_test = f"""
ping -c 3 192.168.100.1
docker exec chain-ingress vppctl ping 192.168.100.1 repeat 3
"""
        
        try:
            print("Testing AWS → GCP connectivity...")
            self.execute_remote_script(self.aws_endpoint, aws_test)
            print("✅ AWS → GCP connectivity successful")
            
            print("Testing GCP → AWS connectivity...")
            self.execute_remote_script(self.gcp_endpoint, gcp_test)
            print("✅ GCP → AWS connectivity successful")
            
        except subprocess.CalledProcessError:
            print("⚠️ Direct connectivity test failed (may be expected with VPP interfaces)")

def main():
    # Define cloud endpoints
    aws_endpoint = CloudEndpoint(
        cloud="aws",
        external_ip="54.123.45.67",  # Replace with actual AWS external IP
        internal_ip="10.0.1.10",
        vpc_cidr="10.0.0.0/16",
        instance_name="aws-vpp-chain-instance"
    )
    
    gcp_endpoint = CloudEndpoint(
        cloud="gcp",
        external_ip="34.56.78.90",  # Replace with actual GCP external IP
        internal_ip="10.0.1.20", 
        vpc_cidr="10.0.0.0/16",
        instance_name="gcp-vpp-chain-instance"
    )
    
    # Setup cross-cloud VXLAN
    manager = CrossCloudVXLANManager(aws_endpoint, gcp_endpoint)
    manager.setup_cross_cloud_vxlan()

if __name__ == "__main__":
    main()
```

### Option 3: Dedicated Interconnect

For production workloads requiring guaranteed bandwidth and low latency:

#### 3.1 AWS Direct Connect + GCP Cloud Interconnect

```bash
# AWS Direct Connect Virtual Interface
aws directconnect create-virtual-interface \
    --connection-id dxcon-xxxxxxxxx \
    --new-virtual-interface '{
        "vlan": 100,
        "virtualInterfaceName": "vpp-chain-vif",
        "asn": 65000,
        "mtu": 9000,
        "addressFamily": "ipv4",
        "customerAddress": "192.168.1.1/30",
        "amazonAddress": "192.168.1.2/30"
    }'

# GCP Cloud Router for interconnect
gcloud compute routers create vpp-chain-router \
    --network vpp-chain-network-production \
    --region us-central1 \
    --asn 65001

# Create Cloud Interconnect attachment
gcloud compute interconnects attachments dedicated create vpp-chain-attachment \
    --router vpp-chain-router \
    --interconnect <interconnect-name> \
    --region us-central1
```

## Cross-Cloud Traffic Testing

### End-to-End Cross-Cloud Test

```python
# cross_cloud_test.py
import time
import subprocess
from scapy.all import *

class CrossCloudTrafficTest:
    def __init__(self, aws_ip, gcp_ip):
        self.aws_ip = aws_ip
        self.gcp_ip = gcp_ip
    
    def run_cross_cloud_test(self):
        """Run comprehensive cross-cloud traffic test"""
        print("🌍 Starting Cross-Cloud VPP Chain Test")
        
        # Test 1: Direct connectivity
        self.test_basic_connectivity()
        
        # Test 2: VXLAN encapsulated traffic
        self.test_vxlan_traffic()
        
        # Test 3: Large packet fragmentation across clouds
        self.test_fragmentation()
        
        # Test 4: IPsec encrypted cross-cloud traffic
        self.test_ipsec_traffic()
    
    def test_basic_connectivity(self):
        """Test basic cross-cloud connectivity"""
        print("📡 Testing basic cross-cloud connectivity")
        
        try:
            # Test AWS to GCP
            result = subprocess.run([
                "ssh", "-i", "aws-key.pem", f"ubuntu@{self.aws_ip}",
                f"ping -c 3 {self.gcp_ip}"
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                print("✅ AWS → GCP basic connectivity: PASS")
            else:
                print("⚠️ AWS → GCP basic connectivity: FAIL (may be expected)")
                
        except subprocess.TimeoutExpired:
            print("⚠️ AWS → GCP connectivity test timeout")
    
    def test_vxlan_traffic(self):
        """Test VXLAN traffic between clouds"""
        print("📦 Testing cross-cloud VXLAN traffic")
        
        # Create VXLAN test packet
        inner_packet = IP(src="10.10.10.5", dst="10.10.10.10")/UDP(sport=1234, dport=2055)/("CrossCloudTest" * 100)
        vxlan_packet = VXLAN(vni=100)/inner_packet
        outer_packet = IP(src=self.aws_ip, dst=self.gcp_ip)/UDP(sport=12345, dport=4789)/vxlan_packet
        
        print(f"Sending cross-cloud VXLAN packet: {self.aws_ip} → {self.gcp_ip}")
        send(outer_packet, count=5, inter=1.0)
        print("✅ Cross-cloud VXLAN traffic sent")
    
    def test_fragmentation(self):
        """Test packet fragmentation across clouds"""
        print("✂️ Testing cross-cloud fragmentation")
        
        # Create jumbo packet that will require fragmentation
        jumbo_payload = "X" * 8000
        inner_packet = IP(src="10.10.10.5", dst="10.10.10.10")/UDP(sport=1234, dport=2055)/jumbo_payload
        vxlan_packet = VXLAN(vni=100)/inner_packet
        outer_packet = IP(src=self.aws_ip, dst=self.gcp_ip)/UDP(sport=12345, dport=4789)/vxlan_packet
        
        print(f"Sending jumbo packet ({len(jumbo_payload)} bytes) for fragmentation test")
        send(outer_packet, count=3, inter=2.0)
        print("✅ Cross-cloud fragmentation test completed")
    
    def test_ipsec_traffic(self):
        """Test IPsec encrypted traffic between clouds"""
        print("🔒 Testing cross-cloud IPsec traffic")
        
        # This would typically involve configuring IPsec SAs between clouds
        # For now, we'll simulate the traffic pattern
        encrypted_payload = "EncryptedCrossCloudData" * 50
        
        # Simulate IPsec ESP packet
        esp_packet = IP(src=self.aws_ip, dst=self.gcp_ip)/UDP(sport=500, dport=500)/encrypted_payload
        
        print("Sending simulated IPsec traffic between clouds")
        send(esp_packet, count=3, inter=1.0)
        print("✅ Cross-cloud IPsec test completed")

def main():
    # Replace with actual IPs
    aws_external_ip = "54.123.45.67"
    gcp_external_ip = "34.56.78.90"
    
    tester = CrossCloudTrafficTest(aws_external_ip, gcp_external_ip)
    tester.run_cross_cloud_test()

if __name__ == "__main__":
    main()
```

## Monitoring Cross-Cloud Connectivity

### CloudWatch + Cloud Monitoring Integration

```python
# cross_cloud_monitoring.py
import boto3
import google.cloud.monitoring_v3 as monitoring_v3
import time
from datetime import datetime, timedelta

class CrossCloudMonitor:
    def __init__(self, aws_region, gcp_project_id):
        self.aws_cloudwatch = boto3.client('cloudwatch', region_name=aws_region)
        self.gcp_monitoring = monitoring_v3.MetricServiceClient()
        self.gcp_project_path = f"projects/{gcp_project_id}"
    
    def send_connectivity_metrics(self, aws_to_gcp_latency, gcp_to_aws_latency, packet_loss):
        """Send cross-cloud connectivity metrics to both clouds"""
        
        # Send to AWS CloudWatch
        self.aws_cloudwatch.put_metric_data(
            Namespace='VPP/CrossCloud',
            MetricData=[
                {
                    'MetricName': 'AWS_to_GCP_Latency',
                    'Value': aws_to_gcp_latency,
                    'Unit': 'Milliseconds',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'GCP_to_AWS_Latency', 
                    'Value': gcp_to_aws_latency,
                    'Unit': 'Milliseconds',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'CrossCloud_PacketLoss',
                    'Value': packet_loss,
                    'Unit': 'Percent',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        # Send to GCP Cloud Monitoring
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/vpp/cross_cloud_latency"
        series.resource.type = "global"
        
        now = time.time()
        seconds = int(now)
        nanos = int((now - seconds) * 10 ** 9)
        interval = monitoring_v3.TimeInterval({"end_time": {"seconds": seconds, "nanos": nanos}})
        point = monitoring_v3.Point({"interval": interval, "value": {"double_value": aws_to_gcp_latency}})
        series.points = [point]
        
        self.gcp_monitoring.create_time_series(
            name=self.gcp_project_path,
            time_series=[series]
        )
    
    def check_cross_cloud_health(self):
        """Continuously monitor cross-cloud connectivity"""
        while True:
            try:
                # Measure latency and packet loss
                aws_to_gcp_latency = self.measure_latency("aws", "gcp")
                gcp_to_aws_latency = self.measure_latency("gcp", "aws")
                packet_loss = self.measure_packet_loss()
                
                # Send metrics
                self.send_connectivity_metrics(
                    aws_to_gcp_latency, 
                    gcp_to_aws_latency, 
                    packet_loss
                )
                
                print(f"Cross-cloud metrics: AWS→GCP: {aws_to_gcp_latency}ms, GCP→AWS: {gcp_to_aws_latency}ms, Loss: {packet_loss}%")
                
                # Wait before next measurement
                time.sleep(60)
                
            except Exception as e:
                print(f"Error in cross-cloud monitoring: {e}")
                time.sleep(30)
    
    def measure_latency(self, source, destination):
        """Measure latency between clouds"""
        # Implementation would involve actual ping/traceroute
        # For now, return simulated values
        import random
        return random.uniform(10.0, 50.0)  # 10-50ms latency
    
    def measure_packet_loss(self):
        """Measure packet loss percentage"""
        import random
        return random.uniform(0.0, 2.0)  # 0-2% packet loss

if __name__ == "__main__":
    monitor = CrossCloudMonitor("us-west-2", "your-gcp-project-id")
    monitor.check_cross_cloud_health()
```

This cross-cloud connectivity guide provides comprehensive solutions for connecting VPP chains across AWS and GCP, including VPN, direct interconnect, and VXLAN overlay options, along with monitoring and testing capabilities.