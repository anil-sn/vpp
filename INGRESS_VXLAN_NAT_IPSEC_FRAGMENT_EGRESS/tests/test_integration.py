#!/usr/bin/env python3
"""
Integration tests for VPP Multi-Container Chain
"""

import unittest
import subprocess
import time
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from utils.container_manager import ContainerManager
from utils.logger import setup_logger

class TestVPPChainIntegration(unittest.TestCase):
    """Integration tests for the complete VPP chain"""
    
    @classmethod
    def setUpClass(cls):
        """Set up test environment"""
        cls.logger = setup_logger("test_integration")
        cls.container_manager = ContainerManager()
        
        # Check if running as root
        if os.geteuid() != 0:
            raise unittest.SkipTest("Integration tests require root privileges")
    
    def test_docker_availability(self):
        """Test that Docker is available and running"""
        try:
            result = subprocess.run(['docker', 'info'], 
                                  capture_output=True, text=True, check=True)
            self.assertIn('Server', result.stdout)
        except subprocess.CalledProcessError:
            self.fail("Docker is not available or not running")
    
    def test_docker_compose_availability(self):
        """Test that docker-compose is available"""
        try:
            result = subprocess.run(['docker-compose', '--version'], 
                                  capture_output=True, text=True, check=True)
            self.assertIn('docker-compose', result.stdout.lower())
        except subprocess.CalledProcessError:
            self.fail("docker-compose is not available")
    
    def test_configuration_files_exist(self):
        """Test that all required configuration files exist"""
        config_files = [
            'src/configs/startup.conf',
            'src/configs/start-vpp.sh',
            'src/configs/ingress-config.sh',
            'src/configs/vxlan-config.sh', 
            'src/configs/nat-config.sh',
            'src/configs/ipsec-config.sh',
            'src/configs/fragment-config.sh',
            'src/configs/gcp-config.sh'
        ]
        
        project_root = os.path.dirname(os.path.dirname(__file__))
        
        for config_file in config_files:
            file_path = os.path.join(project_root, config_file)
            self.assertTrue(os.path.exists(file_path), 
                          f"Configuration file missing: {config_file}")
    
    def test_container_definitions_consistency(self):
        """Test that container definitions match docker-compose.yml"""
        containers = self.container_manager.CONTAINERS
        
        # Test expected container names
        expected_names = [
            'chain-ingress', 'chain-vxlan', 'chain-nat', 
            'chain-ipsec', 'chain-fragment', 'chain-gcp'
        ]
        
        actual_names = [c['name'] for c in containers]
        self.assertEqual(sorted(actual_names), sorted(expected_names))
        
        # Test IP address ranges
        underlay_ips = [c['ip_addresses'].get('underlay') for c in containers 
                       if 'underlay' in c['ip_addresses']]
        
        for ip in underlay_ips:
            if ip:
                self.assertTrue(ip.startswith('192.168.10.'), 
                              f"Underlay IP not in correct range: {ip}")

class TestVPPChainEndToEnd(unittest.TestCase):
    """End-to-end tests that actually run the chain"""
    
    @classmethod
    def setUpClass(cls):
        """Set up for end-to-end testing"""
        if os.geteuid() != 0:
            raise unittest.SkipTest("End-to-end tests require root privileges")
        
        cls.container_manager = ContainerManager()
    
    @unittest.skip("Requires manual intervention and takes significant time")
    def test_full_chain_setup_and_teardown(self):
        """Test complete setup and teardown process"""
        
        # Build images
        self.assertTrue(self.container_manager.build_images(),
                       "Failed to build container images")
        
        # Start containers
        self.assertTrue(self.container_manager.start_containers(),
                       "Failed to start containers")
        
        # Wait for initialization
        time.sleep(30)
        
        # Verify containers
        self.assertTrue(self.container_manager.verify_containers(),
                       "Container verification failed")
        
        # Cleanup
        self.assertTrue(self.container_manager.stop_containers(),
                       "Failed to stop containers")

if __name__ == '__main__':
    # Create test suite
    suite = unittest.TestSuite()
    
    # Add integration tests
    suite.addTest(unittest.makeSuite(TestVPPChainIntegration))
    
    # Add end-to-end tests (usually skipped)
    suite.addTest(unittest.makeSuite(TestVPPChainEndToEnd))
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # Exit with appropriate code
    sys.exit(0 if result.wasSuccessful() else 1)