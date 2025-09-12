#!/usr/bin/env python3
"""
Production Configuration Generator

This script analyzes discovered production environment parameters and generates
a production.json configuration file tailored for the specific deployment environment.
"""

import json
import sys
import os
import socket
import subprocess
import ipaddress
from pathlib import Path
import argparse
import re
from datetime import datetime

class ProductionConfigGenerator:
    def __init__(self, discovery_dir, deployment_type="production"):
        self.discovery_dir = Path(discovery_dir)
        self.deployment_type = deployment_type
        self.discovered_params = {}
        
    def analyze_discovery_reports(self):
        """Analyze discovery reports and extract key parameters"""
        print("Analyzing discovery reports...")
        
        # Parse system information
        self._parse_system_info()
        
        # Parse network configuration
        self._parse_network_config()
        
        # Parse cloud environment
        self._parse_cloud_environment()
        
        # Parse existing applications
        self._parse_applications()
        
        # Parse traffic patterns
        self._parse_traffic_patterns()
        
        print(f"Discovered {len(self.discovered_params)} parameter groups")
        
    def _parse_system_info(self):
        """Parse system information from discovery"""
        system_info_file = self.discovery_dir / "system_info.txt"
        if not system_info_file.exists():
            print("⚠️  System info file not found, using defaults")
            return
            
        content = system_info_file.read_text()
        
        # Extract CPU and memory for container resource allocation
        cpu_match = re.search(r'CPU Cores:\s*(\d+)', content)
        if cpu_match:
            self.discovered_params['cpu_cores'] = int(cpu_match.group(1))
            
        memory_match = re.search(r'Memory:\s*(\d+\.?\d*)([MG])', content)
        if memory_match:
            memory_val = float(memory_match.group(1))
            memory_unit = memory_match.group(2)
            memory_mb = memory_val * 1024 if memory_unit == 'G' else memory_val
            self.discovered_params['memory_mb'] = int(memory_mb)
            
        print(f"System: {self.discovered_params.get('cpu_cores', 'unknown')} CPU cores, "
              f"{self.discovered_params.get('memory_mb', 'unknown')} MB RAM")
            
    def _parse_network_config(self):
        """Parse network configuration to determine container networking"""
        network_file = self.discovery_dir / "network_config.txt"
        if not network_file.exists():
            print("Network config file not found, using defaults")
            return
            
        content = network_file.read_text()
        
        # Extract primary interface and IP
        interface_pattern = r'(\d+):\s*([a-zA-Z0-9]+).*?inet\s+([0-9./]+)'
        matches = re.findall(interface_pattern, content, re.MULTILINE | re.DOTALL)
        
        interfaces = []
        for match in matches:
            iface_name = match[1]
            ip_cidr = match[2]
            
            # Skip loopback and docker interfaces
            if iface_name not in ['lo', 'docker0'] and not iface_name.startswith('veth'):
                try:
                    ip_network = ipaddress.ip_network(ip_cidr, strict=False)
                    interfaces.append({
                        'name': iface_name,
                        'ip': str(ip_network.network_address),
                        'cidr': ip_cidr,
                        'network': str(ip_network)
                    })
                except:
                    continue
                    
        self.discovered_params['interfaces'] = interfaces
        
        # Extract routing information
        route_pattern = r'default via ([0-9.]+)'
        route_match = re.search(route_pattern, content)
        if route_match:
            self.discovered_params['default_gateway'] = route_match.group(1)
            
        primary_interface = interfaces[0] if interfaces else {'name': 'eth0', 'ip': '172.20.100.10'}
        print(f"Primary Interface: {primary_interface['name']} ({primary_interface.get('ip', 'N/A')})")
            
    def _parse_cloud_environment(self):
        """Parse cloud environment for cloud-specific configurations"""
        cloud_file = self.discovery_dir / "cloud_environment.txt"
        if not cloud_file.exists():
            print("Cloud environment file not found")
            self.discovered_params['cloud_provider'] = 'unknown'
            return
            
        content = cloud_file.read_text()
        
        if "AWS Environment Detected" in content:
            self.discovered_params['cloud_provider'] = 'aws'
            
            # Extract AWS parameters
            instance_id_match = re.search(r'Instance ID:\s*([i-\w]+)', content)
            if instance_id_match:
                self.discovered_params['aws_instance_id'] = instance_id_match.group(1)
                
            instance_type_match = re.search(r'Instance Type:\s*([\w.]+)', content)
            if instance_type_match:
                self.discovered_params['aws_instance_type'] = instance_type_match.group(1)
                
            vpc_id_match = re.search(r'VPC ID:\s*(vpc-\w+)', content)
            if vpc_id_match:
                self.discovered_params['aws_vpc_id'] = vpc_id_match.group(1)
                
        elif "GCP Environment Detected" in content:
            self.discovered_params['cloud_provider'] = 'gcp'
            
            # Extract GCP parameters
            project_match = re.search(r'Project ID:\s*([a-zA-Z0-9-]+)', content)
            if project_match:
                self.discovered_params['gcp_project_id'] = project_match.group(1)
                
            zone_match = re.search(r'Zone:\s*([\w-]+)', content)
            if zone_match:
                self.discovered_params['gcp_zone'] = zone_match.group(1)
                
        elif "Azure Environment Detected" in content:
            self.discovered_params['cloud_provider'] = 'azure'
            
        else:
            self.discovered_params['cloud_provider'] = 'on_premises'
            
        print(f"Cloud Provider: {self.discovered_params['cloud_provider']}")
            
    def _parse_applications(self):
        """Parse existing applications to avoid conflicts"""
        app_file = self.discovery_dir / "application_discovery.txt"
        if not app_file.exists():
            return
            
        content = app_file.read_text()
        
        # Check for existing VPP installation
        if "VPP Version:" in content and "not detected" not in content:
            self.discovered_params['existing_vpp'] = True
            print("Existing VPP installation detected")
        else:
            self.discovered_params['existing_vpp'] = False
            print("No existing VPP conflicts detected")
            
        # Check for Docker
        if "Docker Version:" in content and "not detected" not in content:
            self.discovered_params['docker_available'] = True
            print("Docker available for container deployment")
        else:
            self.discovered_params['docker_available'] = False
            print("Docker not available - installation required")
            
        # Extract listening ports to avoid conflicts
        port_pattern = r':(\d+)\s'
        ports = re.findall(port_pattern, content)
        self.discovered_params['used_ports'] = [int(p) for p in ports if p.isdigit()]
        
    def _parse_traffic_patterns(self):
        """Parse traffic patterns to understand integration requirements"""
        traffic_dir = self.discovery_dir / "traffic_integration"
        if not traffic_dir.exists():
            return
            
        # Check for VXLAN traffic
        vxlan_file = traffic_dir / "vxlan_detection.txt"
        try:
            if vxlan_file.exists():
                content = vxlan_file.read_text()
                if "VXLAN traffic detected" in content:
                    self.discovered_params['existing_vxlan'] = True
                    print("Existing VXLAN traffic detected - integration mode required")
                else:
                    self.discovered_params['existing_vxlan'] = False
                    print("No conflicting VXLAN traffic detected")
            else:
                self.discovered_params['existing_vxlan'] = False
                print("No conflicting VXLAN traffic detected")
        except PermissionError:
            print("Traffic integration file access denied, assuming no conflicts")
            self.discovered_params['existing_vxlan'] = False
    
    def generate_production_config(self):
        """Generate production.json configuration based on discovered parameters"""
        print("Generating production configuration...")
        
        # Base configuration template
        config = {
            "default_mode": "production",
            "description": f"Production configuration generated from environment discovery on {self.discovered_params.get('cloud_provider', 'unknown')} infrastructure",
            "deployment_metadata": {
                "generated_at": datetime.now().isoformat(),
                "source_discovery": str(self.discovery_dir),
                "cloud_provider": self.discovered_params.get('cloud_provider', 'unknown'),
                "system_specs": {
                    "cpu_cores": self.discovered_params.get('cpu_cores', 4),
                    "memory_mb": self.discovered_params.get('memory_mb', 8192),
                    "interfaces": len(self.discovered_params.get('interfaces', []))
                }
            },
            "modes": {
                "production": self._generate_production_mode_config()
            }
        }
        
        return config
        
    def _generate_production_mode_config(self):
        """Generate production mode configuration based on discovered environment"""
        # Determine network configuration based on discovered parameters
        primary_interface = self.discovered_params.get('interfaces', [{}])[0]
        base_ip = primary_interface.get('ip', '172.20.100.0')
        
        # Calculate production network ranges avoiding conflicts with existing infrastructure
        try:
            # Parse existing IP to determine safe network ranges
            existing_network = ipaddress.ip_network(f"{base_ip}/24", strict=False)
            base_octet = int(str(existing_network.network_address).split('.')[2])
            
            # Use different /24 networks to avoid conflicts
            external_network = f"172.20.{base_octet + 10}.0/24"
            processing_network = f"172.20.{base_octet + 11}.0/24"
            destination_network = f"172.20.{base_octet + 12}.0/24"
            
        except:
            # Safe defaults if parsing fails
            external_network = "172.20.110.0/24"
            processing_network = "172.20.111.0/24"
            destination_network = "172.20.112.0/24"
        
        # Resource allocation based on discovered system specs
        cpu_cores = self.discovered_params.get('cpu_cores', 4)
        memory_mb = self.discovered_params.get('memory_mb', 8192)
        
        # Conservative resource allocation for production stability
        container_memory = min(2048, memory_mb // 4)  # Max 2GB per container
        container_cpus = max(1, cpu_cores // 4)       # At least 1 CPU per container
        
        production_config = {
            "description": f"Production deployment on {self.discovered_params.get('cloud_provider', 'detected')} infrastructure",
            "resource_allocation": {
                "container_memory_mb": container_memory,
                "container_cpu_cores": container_cpus,
                "total_system_cores": cpu_cores,
                "total_system_memory_mb": memory_mb,
                "resource_reservation_percent": 75  # Leave 25% for system overhead
            },
            "networks": [
                {
                    "name": "external-traffic",
                    "subnet": external_network,
                    "gateway": external_network.replace('0/24', '1'),
                    "description": f"External traffic network (isolated from {primary_interface.get('name', 'existing')})",
                    "mtu": 1500
                },
                {
                    "name": "vxlan-processing",
                    "subnet": processing_network,
                    "gateway": processing_network.replace('0/24', '1'),
                    "description": "VXLAN to Security Processor communication",
                    "mtu": 9000
                },
                {
                    "name": "processing-destination",
                    "subnet": destination_network,
                    "gateway": destination_network.replace('0/24', '1'),
                    "description": "Security Processor to Destination communication",
                    "mtu": 9000
                }
            ],
            "containers": self._generate_container_configs(external_network, processing_network, destination_network),
            "traffic_config": {
                "vxlan_port": 4789,
                "vxlan_vni": 100,
                "production_validation": {
                    "min_success_rate_percent": 90,
                    "max_latency_ms": 50,
                    "test_protocols": ["netflow", "sflow", "ipfix"]
                }
            }
        }
        
        return production_config
    
    def _generate_container_configs(self, external_net, processing_net, destination_net):
        """Generate production-ready container configurations"""
        memory_per_container = self.discovered_params.get('memory_mb', 8192) // 4
        cpu_per_container = max(1.0, self.discovered_params.get('cpu_cores', 4) / 4)
        
        return {
            "vxlan-processor": {
                "description": "Production VXLAN decapsulation with BVI L2-to-L3 conversion",
                "dockerfile": "src/containers/Dockerfile.vxlan",
                "config_script": "src/containers/vxlan-config.sh",
                "resource_limits": {
                    "memory": f"{memory_per_container}m",
                    "cpus": str(cpu_per_container),
                    "restart_policy": "always"
                },
                "interfaces": [
                    {
                        "name": "eth0",
                        "network": "external-traffic",
                        "ip": {"address": external_net.replace('0/24', '10'), "mask": 24}
                    },
                    {
                        "name": "eth1",
                        "network": "vxlan-processing", 
                        "ip": {"address": processing_net.replace('0/24', '10'), "mask": 24}
                    }
                ]
            },
            "security-processor": {
                "description": "Production NAT44 + IPsec + Fragmentation processing",
                "dockerfile": "src/containers/Dockerfile.security",
                "config_script": "src/containers/security-config.sh",
                "resource_limits": {
                    "memory": f"{memory_per_container}m",
                    "cpus": str(cpu_per_container),
                    "restart_policy": "always"
                },
                "interfaces": [
                    {
                        "name": "eth0",
                        "network": "vxlan-processing",
                        "ip": {"address": processing_net.replace('0/24', '20'), "mask": 24}
                    },
                    {
                        "name": "eth1",
                        "network": "processing-destination",
                        "ip": {"address": destination_net.replace('0/24', '10'), "mask": 24}
                    }
                ]
            },
            "destination": {
                "description": "Production destination with TAP interface",
                "dockerfile": "src/containers/Dockerfile.destination",
                "config_script": "src/containers/destination-config.sh",
                "resource_limits": {
                    "memory": f"{memory_per_container}m",
                    "cpus": str(cpu_per_container),
                    "restart_policy": "always"
                },
                "interfaces": [
                    {
                        "name": "eth0",
                        "network": "processing-destination",
                        "ip": {"address": destination_net.replace('0/24', '20'), "mask": 24}
                    }
                ]
            }
        }

    def save_config(self, config, output_file="production_generated.json"):
        """Save generated configuration to file"""
        output_path = Path(output_file)
        
        with open(output_path, 'w') as f:
            json.dump(config, f, indent=2, sort_keys=True)
            
        print(f"Production configuration saved to: {output_path.absolute()}")
        return output_path

def main():
    parser = argparse.ArgumentParser(description='Generate production VPP configuration from environment discovery')
    parser.add_argument('discovery_dir', help='Directory containing discovery reports')
    parser.add_argument('--output', '-o', default='production_generated.json', help='Output configuration file')
    parser.add_argument('--deployment-type', '-t', default='production', help='Deployment type')
    parser.add_argument('--validate', '-v', action='store_true', help='Validate generated configuration')
    
    args = parser.parse_args()
    
    if not Path(args.discovery_dir).exists():
        print(f"Discovery directory not found: {args.discovery_dir}")
        sys.exit(1)
    
    # Generate configuration
    generator = ProductionConfigGenerator(args.discovery_dir, args.deployment_type)
    generator.analyze_discovery_reports()
    config = generator.generate_production_config()
    
    # Save configuration
    output_path = generator.save_config(config, args.output)
    
    # Validate if requested
    if args.validate:
        try:
            with open(output_path) as f:
                json.load(f)
            print("Generated configuration is valid JSON")
        except Exception as e:
            print(f"Configuration validation failed: {e}")
            sys.exit(1)
    
    print("\nProduction configuration generation completed successfully!")
    print(f"Config file: {output_path.absolute()}")
    print("\nNext steps:")
    print("1. Review the generated configuration file")
    print("2. Customize any specific production requirements")
    print(f"3. Deploy using: sudo python3 src/main.py setup --config {output_path}")

if __name__ == "__main__":
    main()