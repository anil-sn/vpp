#!/usr/bin/env python3
"""
Multi-Cloud VPP Chain Configuration Generator

This interactive script collects information about your AWS and GCP environments
and generates production configuration files for distributed VPP chain deployment:

AWS VM: VXLAN-PROCESSOR → SECURITY-PROCESSOR  
GCP VM: DESTINATION

The script generates:
- production_aws_config.json (for AWS VM deployment)
- production_gcp_config.json (for GCP VM deployment)
- cross_cloud_diagnostics.py (validation and testing script)
"""

import json
import sys
import ipaddress
from datetime import datetime
import os
import socket

class MultiCloudConfigGenerator:
    def __init__(self):
        self.aws_config = {}
        self.gcp_config = {}
        self.cross_cloud_config = {}
        
    def print_header(self):
        print("=" * 80)
        print("  VPP Multi-Cloud Chain Configuration Generator")
        print("=" * 80)
        print()
        print("Deployment Architecture:")
        print("  AWS VM: [VXLAN-PROCESSOR] → [SECURITY-PROCESSOR]")
        print("                                        ↓")
        print("                              AWS-GCP VPN/Interconnect")
        print("                                        ↓")
        print("  GCP VM:                    [DESTINATION]")
        print()
        print("This script will generate:")
        print("   production_aws_config.json")
        print("   production_gcp_config.json") 
        print("   cross_cloud_diagnostics.py")
        print()
        
    def collect_aws_info(self):
        print(" AWS Environment Configuration")
        print("-" * 40)
        
        # AWS Basic Info
        aws_region = input("AWS Region (e.g., us-west-2): ").strip() or "us-west-2"
        aws_az = input("AWS Availability Zone (e.g., us-west-2c): ").strip() or f"{aws_region}c"
        aws_instance_type = input("AWS Instance Type (e.g., t3.large): ").strip() or "t3.large"
        
        # AWS VPC and Network Info
        print("\n AWS Network Configuration:")
        aws_vpc_id = input("AWS VPC ID (e.g., vpc-0e08244d9406db633): ").strip()
        aws_subnet_id = input("AWS Private Subnet ID: ").strip()
        
        # AWS Interface Configuration
        print("\n AWS Interface Configuration:")
        aws_primary_interface = input("Primary Interface Name (default: ens5): ").strip() or "ens5"
        aws_primary_ip = input(f"Current {aws_primary_interface} IP/CIDR (e.g., 172.30.82.115/23): ").strip()
        
        aws_bridge_name = input("Existing Bridge Name (default: br0): ").strip() or "br0"
        aws_bridge_ip = input(f"Current {aws_bridge_name} IP/CIDR (e.g., 172.30.83.161/23): ").strip()
        
        aws_vxlan_interface = input("Existing VXLAN Interface (default: vxlan1): ").strip() or "vxlan1"
        aws_vxlan_vni = input("VXLAN VNI (default: 1): ").strip() or "1"
        
        # AWS Internal Networks for VPP
        print("\n  AWS VPP Internal Networks:")
        aws_vxlan_processing_net = input("VXLAN Processing Network (default: 192.168.100.0/24): ").strip() or "192.168.100.0/24"
        aws_security_processing_net = input("Security Processing Network (default: 192.168.101.0/24): ").strip() or "192.168.101.0/24"
        
        self.aws_config = {
            "region": aws_region,
            "availability_zone": aws_az,
            "instance_type": aws_instance_type,
            "vpc_id": aws_vpc_id,
            "subnet_id": aws_subnet_id,
            "primary_interface": aws_primary_interface,
            "primary_ip": aws_primary_ip,
            "bridge_name": aws_bridge_name,
            "bridge_ip": aws_bridge_ip,
            "vxlan_interface": aws_vxlan_interface,
            "vxlan_vni": int(aws_vxlan_vni),
            "vxlan_processing_network": aws_vxlan_processing_net,
            "security_processing_network": aws_security_processing_net
        }
        
    def collect_gcp_info(self):
        print("\n GCP Environment Configuration")
        print("-" * 40)
        
        # GCP Basic Info
        gcp_project_id = input("GCP Project ID: ").strip()
        gcp_region = input("GCP Region (e.g., us-central1): ").strip() or "us-central1"
        gcp_zone = input("GCP Zone (e.g., us-central1-a): ").strip() or f"{gcp_region}-a"
        gcp_instance_type = input("GCP Instance Type (e.g., e2-standard-2): ").strip() or "e2-standard-2"
        
        # GCP Network Info
        print("\n GCP Network Configuration:")
        gcp_vpc_name = input("GCP VPC Network Name: ").strip()
        gcp_subnet_name = input("GCP Subnet Name: ").strip()
        gcp_internal_ip = input("GCP VM Internal IP/CIDR (e.g., 10.0.1.100/24): ").strip()
        
        # GCP TAP Configuration
        print("\n GCP TAP Interface Configuration:")
        gcp_tap_network = input("TAP Interface Network (default: 10.0.3.0/24): ").strip() or "10.0.3.0/24"
        gcp_tap_ip = input("TAP Interface IP (default: 10.0.3.1): ").strip() or "10.0.3.1"
        
        self.gcp_config = {
            "project_id": gcp_project_id,
            "region": gcp_region,
            "zone": gcp_zone,
            "instance_type": gcp_instance_type,
            "vpc_name": gcp_vpc_name,
            "subnet_name": gcp_subnet_name,
            "internal_ip": gcp_internal_ip,
            "tap_network": gcp_tap_network,
            "tap_ip": gcp_tap_ip
        }
        
    def collect_cross_cloud_info(self):
        print("\n Cross-Cloud Connectivity Configuration")
        print("-" * 40)
        
        # Connectivity Method
        print("Select connectivity method:")
        print("1. VPN Gateway (Cloud VPN)")
        print("2. Dedicated Interconnect") 
        print("3. VPC Peering (if same cloud provider)")
        print("4. Public Internet with IPsec")
        
        connectivity_method = input("Choose option (1-4, default: 1): ").strip() or "1"
        
        # Cross-cloud network
        cross_cloud_network = input("Cross-cloud Transit Network (default: 192.168.200.0/24): ").strip() or "192.168.200.0/24"
        
        # AWS to GCP communication
        aws_to_gcp_ip = input("AWS Security Processor → GCP IP (default: 192.168.200.1): ").strip() or "192.168.200.1"
        gcp_from_aws_ip = input("GCP Destination ← AWS IP (default: 192.168.200.2): ").strip() or "192.168.200.2"
        
        # VPN Configuration (if selected)
        vpn_config = {}
        if connectivity_method == "1":
            print("\n VPN Configuration:")
            vpn_config["aws_vpn_gateway_id"] = input("AWS VPN Gateway ID: ").strip()
            vpn_config["gcp_vpn_gateway_name"] = input("GCP VPN Gateway Name: ").strip()
            vpn_config["shared_secret"] = input("VPN Shared Secret: ").strip()
            vpn_config["aws_customer_gateway_ip"] = input("AWS Customer Gateway IP: ").strip()
            vpn_config["gcp_peer_ip"] = input("GCP Peer IP: ").strip()
        
        # IPsec Configuration for VPP
        print("\n IPsec Configuration for VPP:")
        ipsec_crypto_key = input("IPsec Crypto Key (hex, default: auto-generate): ").strip()
        ipsec_integ_key = input("IPsec Integrity Key (hex, default: auto-generate): ").strip()
        
        if not ipsec_crypto_key:
            ipsec_crypto_key = "0x" + "01234567890abcdef" * 4  # 32 bytes for AES-256
        if not ipsec_integ_key:
            ipsec_integ_key = "0x" + "01234567890abcdef" * 2   # 16 bytes for SHA-256
            
        self.cross_cloud_config = {
            "connectivity_method": connectivity_method,
            "cross_cloud_network": cross_cloud_network,
            "aws_to_gcp_ip": aws_to_gcp_ip,
            "gcp_from_aws_ip": gcp_from_aws_ip,
            "vpn_config": vpn_config,
            "ipsec": {
                "crypto_key": ipsec_crypto_key,
                "integ_key": ipsec_integ_key,
                "crypto_alg": "aes-gcm-128",
                "spi_out": 2000,
                "spi_in": 2001
            }
        }
        
    def collect_traffic_info(self):
        print("\n Traffic Configuration")
        print("-" * 40)
        
        # NAT Configuration
        print("NAT44 Configuration:")
        nat_inside_network = input("NAT Inside Network (default: 10.10.10.0/24): ").strip() or "10.10.10.0/24"
        nat_outside_ip = input("NAT Outside IP (will be GCP destination IP): ").strip() or self.cross_cloud_config["gcp_from_aws_ip"]
        
        # Traffic mirroring info
        print("\nTraffic Mirroring Configuration:")
        source_port = input("Source UDP Port (default: any): ").strip() or "any"
        dest_port = input("Destination UDP Port (default: 2055 for NetFlow): ").strip() or "2055"
        
        self.traffic_config = {
            "nat44": {
                "inside_network": nat_inside_network,
                "outside_ip": nat_outside_ip,
                "source_port": source_port,
                "dest_port": dest_port
            }
        }
        
    def validate_configuration(self):
        print("\n Configuration Validation")
        print("-" * 40)
        
        issues = []
        
        # Validate IP addresses
        try:
            ipaddress.IPv4Interface(self.aws_config["primary_ip"])
        except:
            issues.append("Invalid AWS primary IP address")
            
        try:
            ipaddress.IPv4Interface(self.gcp_config["internal_ip"])
        except:
            issues.append("Invalid GCP internal IP address")
            
        # Check network connectivity potential
        aws_network = ipaddress.IPv4Network(self.aws_config["vxlan_processing_network"], strict=False)
        gcp_network = ipaddress.IPv4Network(self.gcp_config["tap_network"], strict=False)
        cross_network = ipaddress.IPv4Network(self.cross_cloud_config["cross_cloud_network"], strict=False)
        
        if aws_network.overlaps(gcp_network):
            issues.append("AWS and GCP networks overlap - this may cause routing issues")
            
        if issues:
            print("  Configuration Issues Found:")
            for issue in issues:
                print(f"  • {issue}")
            if input("\nContinue anyway? (y/N): ").lower() != 'y':
                sys.exit(1)
        else:
            print("Configuration validation passed")
            
    def generate_aws_config(self):
        """Generate production_aws_config.json"""
        
        # Parse AWS primary IP for network calculation
        aws_primary_net = ipaddress.IPv4Interface(self.aws_config["primary_ip"]).network
        aws_gateway = str(list(aws_primary_net.hosts())[0])  # First host as gateway
        
        config = {
            "default_mode": "aws_multicloud_production",
            "description": "Production AWS configuration - VXLAN + Security processors for multi-cloud chain",
            "modes": {
                "aws_multicloud_production": {
                    "description": "AWS side: VXLAN processor + Security processor → GCP destination",
                    "environment": {
                        "type": "production",
                        "cloud": "aws",
                        "region": self.aws_config["region"],
                        "availability_zone": self.aws_config["availability_zone"],
                        "instance_type": self.aws_config["instance_type"],
                        "vpc_id": self.aws_config["vpc_id"],
                        "subnet_id": self.aws_config["subnet_id"]
                    },
                    "networks": [
                        {
                            "name": "aws-vxlan-ingress",
                            "subnet": str(aws_primary_net),
                            "gateway": aws_gateway,
                            "description": f"AWS {self.aws_config['primary_interface']} VXLAN traffic ingress",
                            "mtu": 9000,
                            "host_integration": {
                                "interface": self.aws_config["primary_interface"],
                                "bridge": self.aws_config["bridge_name"],
                                "vxlan_interface": self.aws_config["vxlan_interface"]
                            }
                        },
                        {
                            "name": "aws-vxlan-processing",
                            "subnet": self.aws_config["vxlan_processing_network"],
                            "gateway": str(ipaddress.IPv4Network(self.aws_config["vxlan_processing_network"]).network_address + 1),
                            "description": "VXLAN to Security processor communication",
                            "mtu": 9000
                        },
                        {
                            "name": "aws-cross-cloud",
                            "subnet": self.cross_cloud_config["cross_cloud_network"],
                            "gateway": str(ipaddress.IPv4Network(self.cross_cloud_config["cross_cloud_network"]).network_address + 1),
                            "description": "AWS to GCP cross-cloud communication",
                            "vpn_integration": self.cross_cloud_config.get("vpn_config", {})
                        }
                    ],
                    "containers": {
                        "vxlan-processor": {
                            "description": "VXLAN decapsulation with BVI L2-to-L3 conversion",
                            "dockerfile": "src/containers/Dockerfile.vxlan",
                            "config_script": "vxlan-config.sh",
                            "privileged": True,
                            "interfaces": [
                                {
                                    "name": "eth0",
                                    "network": "aws-vxlan-ingress",
                                    "ip": {"address": str(list(aws_primary_net.hosts())[-10]), "mask": aws_primary_net.prefixlen},
                                    "description": f"Receive VXLAN from {self.aws_config['vxlan_interface']}"
                                },
                                {
                                    "name": "eth1", 
                                    "network": "aws-vxlan-processing",
                                    "ip": {"address": str(ipaddress.IPv4Network(self.aws_config["vxlan_processing_network"]).network_address + 10), "mask": ipaddress.IPv4Network(self.aws_config["vxlan_processing_network"]).prefixlen},
                                    "description": "Forward to security processor"
                                }
                            ],
                            "vxlan_tunnel": {
                                "src": str(list(aws_primary_net.hosts())[-10]),
                                "dst": aws_gateway,
                                "vni": self.aws_config["vxlan_vni"],
                                "port": 4789
                            },
                            "bvi": {
                                "ip": "192.168.201.1/24"
                            }
                        },
                        "security-processor": {
                            "description": "NAT44 + IPsec ESP processing for cross-cloud transmission",
                            "dockerfile": "src/containers/Dockerfile.security",
                            "config_script": "security-config.sh", 
                            "privileged": True,
                            "interfaces": [
                                {
                                    "name": "eth0",
                                    "network": "aws-vxlan-processing", 
                                    "ip": {"address": str(ipaddress.IPv4Network(self.aws_config["vxlan_processing_network"]).network_address + 20), "mask": ipaddress.IPv4Network(self.aws_config["vxlan_processing_network"]).prefixlen},
                                    "description": "Receive from VXLAN processor"
                                },
                                {
                                    "name": "eth1",
                                    "network": "aws-cross-cloud",
                                    "ip": {"address": self.cross_cloud_config["aws_to_gcp_ip"], "mask": ipaddress.IPv4Network(self.cross_cloud_config["cross_cloud_network"]).prefixlen},
                                    "description": "Send to GCP destination via VPN/interconnect"
                                }
                            ],
                            "nat44": {
                                "interface_flags": [
                                    {"interface": "eth0", "flag": "in"},
                                    {"interface": "eth1", "flag": "out"}
                                ],
                                "static_mappings": [
                                    {
                                        "local_ip": "10.10.10.10", "local_port": 2055,
                                        "external_ip": self.cross_cloud_config["gcp_from_aws_ip"], "external_port": 2055,
                                        "protocol": "udp"
                                    }
                                ]
                            },
                            "ipsec": self.cross_cloud_config["ipsec"]
                        }
                    },
                    "cross_cloud": {
                        "destination_cloud": "gcp",
                        "connectivity": self.cross_cloud_config["connectivity_method"],
                        "target_ip": self.cross_cloud_config["gcp_from_aws_ip"]
                    }
                }
            }
        }
        
        return config
        
    def generate_gcp_config(self):
        """Generate production_gcp_config.json"""
        
        gcp_internal_net = ipaddress.IPv4Interface(self.gcp_config["internal_ip"]).network
        gcp_gateway = str(list(gcp_internal_net.hosts())[0])
        
        config = {
            "default_mode": "gcp_multicloud_production",
            "description": "Production GCP configuration - Destination processor for multi-cloud chain",
            "modes": {
                "gcp_multicloud_production": {
                    "description": "GCP side: Destination processor receiving from AWS",
                    "environment": {
                        "type": "production",
                        "cloud": "gcp",
                        "project_id": self.gcp_config["project_id"],
                        "region": self.gcp_config["region"],
                        "zone": self.gcp_config["zone"],
                        "instance_type": self.gcp_config["instance_type"],
                        "vpc_name": self.gcp_config["vpc_name"],
                        "subnet_name": self.gcp_config["subnet_name"]
                    },
                    "networks": [
                        {
                            "name": "gcp-cross-cloud",
                            "subnet": self.cross_cloud_config["cross_cloud_network"],
                            "gateway": str(ipaddress.IPv4Network(self.cross_cloud_config["cross_cloud_network"]).network_address + 1),
                            "description": "GCP from AWS cross-cloud communication",
                            "vpn_integration": self.cross_cloud_config.get("vpn_config", {})
                        },
                        {
                            "name": "gcp-internal",
                            "subnet": str(gcp_internal_net),
                            "gateway": gcp_gateway,
                            "description": "GCP internal network for final delivery",
                            "mtu": 1500
                        }
                    ],
                    "containers": {
                        "destination": {
                            "description": "ESP decryption + packet reassembly + TAP delivery",
                            "dockerfile": "src/containers/Dockerfile.destination",
                            "config_script": "destination-config.sh",
                            "privileged": True,
                            "interfaces": [
                                {
                                    "name": "eth0",
                                    "network": "gcp-cross-cloud",
                                    "ip": {"address": self.cross_cloud_config["gcp_from_aws_ip"], "mask": ipaddress.IPv4Network(self.cross_cloud_config["cross_cloud_network"]).prefixlen},
                                    "promiscuous": True,
                                    "description": "Receive encrypted packets from AWS security processor"
                                }
                            ],
                            "tap_interface": {
                                "name": "tap0",
                                "ip": f"{self.gcp_config['tap_ip']}/{ipaddress.IPv4Network(self.gcp_config['tap_network']).prefixlen}",
                                "rx_mode": "interrupt",
                                "promiscuous": True,
                                "description": "Final packet delivery for analysis/forwarding"
                            },
                            "ipsec_decrypt": self.cross_cloud_config["ipsec"]
                        }
                    },
                    "cross_cloud": {
                        "source_cloud": "aws",
                        "connectivity": self.cross_cloud_config["connectivity_method"],
                        "source_ip": self.cross_cloud_config["aws_to_gcp_ip"]
                    }
                }
            }
        }
        
        return config
    
    def save_configs(self):
        """Save generated configurations to files"""
        
        # Generate configurations
        aws_config = self.generate_aws_config()
        gcp_config = self.generate_gcp_config()
        
        # Save AWS config
        with open("production_aws_config.json", "w") as f:
            json.dump(aws_config, f, indent=2)
        print(f"Generated: production_aws_config.json")
        
        # Save GCP config  
        with open("production_gcp_config.json", "w") as f:
            json.dump(gcp_config, f, indent=2)
        print(f"Generated: production_gcp_config.json")
        
        # Save combined metadata for diagnostics
        metadata = {
            "generated_at": datetime.now().isoformat(),
            "aws": self.aws_config,
            "gcp": self.gcp_config,
            "cross_cloud": self.cross_cloud_config,
            "traffic": getattr(self, 'traffic_config', {})
        }
        
        with open("multicloud_deployment_metadata.json", "w") as f:
            json.dump(metadata, f, indent=2)
        print(f"Generated: multicloud_deployment_metadata.json")
        
    def print_summary(self):
        print("\n" + "=" * 80)
        print("Multi-Cloud VPP Chain Configuration Complete!")
        print("=" * 80)
        print()
        print("Generated Files:")
        print("   production_aws_config.json     - AWS VM configuration")
        print("   production_gcp_config.json     - GCP VM configuration") 
        print("   multicloud_deployment_metadata.json - Deployment metadata")
        print()
        print("Next Steps:")
        print("  1. Copy production_aws_config.json to your AWS VM")
        print("  2. Copy production_gcp_config.json to your GCP VM")
        print("  3. Run deployment scripts on each VM:")
        print("       AWS: sudo ./deploy_aws_multicloud.sh")
        print("       GCP: sudo ./deploy_gcp_multicloud.sh")
        print("  4. Run cross-cloud diagnostics:")
        print("       python3 cross_cloud_diagnostics.py")
        print()
        print("Architecture Summary:")
        print(f"   AWS ({self.aws_config['region']}):")
        print(f"      • VXLAN Processor: {self.aws_config['vxlan_interface']} → VPP decap")
        print(f"      • Security Processor: NAT44 + IPsec → {self.cross_cloud_config['aws_to_gcp_ip']}")
        print()
        print(f"   GCP ({self.gcp_config['region']}):")
        print(f"      • Destination: {self.cross_cloud_config['gcp_from_aws_ip']} → ESP decrypt → {self.gcp_config['tap_ip']}")
        print()
        print("Cross-Cloud Connection:")
        connectivity_map = {
            "1": "VPN Gateway",
            "2": "Dedicated Interconnect", 
            "3": "VPC Peering",
            "4": "Public Internet with IPsec"
        }
        print(f"    Method: {connectivity_map.get(self.cross_cloud_config['connectivity_method'], 'Unknown')}")
        print(f"    Network: {self.cross_cloud_config['cross_cloud_network']}")
        print()

def main():
    generator = MultiCloudConfigGenerator()
    
    generator.print_header()
    
    try:
        generator.collect_aws_info()
        generator.collect_gcp_info()
        generator.collect_cross_cloud_info()
        generator.collect_traffic_info()
        
        generator.validate_configuration()
        generator.save_configs()
        generator.print_summary()
        
    except KeyboardInterrupt:
        print("\n\n Configuration cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n💥 Error during configuration: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()