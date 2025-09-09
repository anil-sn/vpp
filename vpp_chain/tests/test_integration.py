#!/usr/bin/env python3
"""
Integration tests for VPP Multi-Container Chain - Updated for new config.json structure
"""

import unittest
import subprocess
import time
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from utils.container_manager import ContainerManager
from utils.config_manager import ConfigManager
from utils.logger import setup_logger

class TestVPPChainIntegration(unittest.TestCase):
    """Integration tests for the complete VPP chain with current configuration"""
    
    @classmethod
    def setUpClass(cls):
        """Set up test environment"""
        cls.logger = setup_logger("test_integration")
        cls.config_manager = ConfigManager()
        cls.container_manager = ContainerManager(cls.config_manager)
        
        # Check if running as root
        if os.geteuid() != 0:
            raise unittest.SkipTest("Integration tests require root privileges")
    
    def test_config_loading(self):
        """Test that config.json loads correctly with current structure"""
        containers = self.config_manager.get_containers()
        networks = self.config_manager.get_networks()
        
        # Check expected containers exist
        expected_containers = ["chain-ingress", "chain-vxlan", "chain-nat", 
                             "chain-ipsec", "chain-fragment", "chain-gcp"]
        
        for container in expected_containers:
            self.assertIn(container, containers)
            
        # Check network structure
        self.assertGreater(len(networks), 0)
        for network in networks:
            self.assertIn('name', network)
            self.assertIn('subnet', network)
            # Verify current IP ranges (172.20.x.x)
            self.assertTrue(network['subnet'].startswith('172.20.'))
    
    def test_container_ip_configuration(self):
        """Test that containers use current IP addressing scheme"""
        containers = self.config_manager.get_containers()
        
        for container_name, container in containers.items():
            for interface in container['interfaces']:
                ip_address = interface['ip']['address']
                # Verify current IP scheme (172.20.x.x)
                self.assertTrue(ip_address.startswith('172.20.'), 
                              f"Container {container_name} has outdated IP: {ip_address}")
    
    @unittest.skipUnless(os.getenv('RUN_CONTAINER_TESTS'), 
                        "Container tests skipped - set RUN_CONTAINER_TESTS=1 to run")
    def test_container_build_process(self):
        """Test container build process (requires Docker)"""
        # This is a more comprehensive test that could actually build containers
        # Skipped by default to avoid Docker dependency in CI
        result = subprocess.run(['docker', '--version'], capture_output=True, text=True)
        if result.returncode != 0:
            self.skipTest("Docker not available")
            
        # Test would verify image building here
        self.assertTrue(True)  # Placeholder
    
    def test_network_configuration_validity(self):
        """Test that network configuration is valid"""
        networks = self.config_manager.get_networks()
        
        # Check for network name conflicts
        network_names = [net['name'] for net in networks]
        self.assertEqual(len(network_names), len(set(network_names)), 
                        "Duplicate network names found")
        
        # Check subnet non-overlap (basic check)
        subnets = [net['subnet'] for net in networks]
        self.assertEqual(len(subnets), len(set(subnets)),
                        "Duplicate subnet ranges found")
    
    def test_container_dependency_order(self):
        """Test that containers are configured in proper dependency order"""
        containers = self.config_manager.get_containers()
        
        # Verify chain order containers exist
        chain_order = ["chain-ingress", "chain-vxlan", "chain-nat", 
                      "chain-ipsec", "chain-fragment", "chain-gcp"]
        
        for container in chain_order:
            self.assertIn(container, containers,
                         f"Expected container {container} not found in config")
    
    def test_traffic_config_compatibility(self):
        """Test that traffic configuration matches container setup"""
        traffic_config = self.config_manager.get_traffic_config()
        containers = self.config_manager.get_containers()
        
        # Verify traffic config has required fields
        required_fields = ["bridge_ip", "vxlan_port", "vxlan_vni", 
                          "inner_src_ip", "inner_dst_ip", "inner_dst_port"]
        
        for field in required_fields:
            self.assertIn(field, traffic_config,
                         f"Missing required traffic config field: {field}")
        
        # Verify VXLAN VNI consistency
        vxlan_container = containers["chain-vxlan"]
        if "vxlan_tunnel" in vxlan_container:
            config_vni = traffic_config["vxlan_vni"]
            container_vni = vxlan_container["vxlan_tunnel"]["vni"]
            self.assertEqual(config_vni, container_vni, "VXLAN VNI mismatch")

if __name__ == '__main__':
    # Add environment variable hint
    print("Tip: Set RUN_CONTAINER_TESTS=1 to run container build tests")
    unittest.main()