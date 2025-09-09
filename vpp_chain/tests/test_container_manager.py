#!/usr/bin/env python3
"""
Unit tests for ContainerManager - Updated for new config.json structure
"""

import unittest
import sys
import os
from unittest.mock import Mock, patch, MagicMock

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from utils.container_manager import ContainerManager
from utils.config_manager import ConfigManager

class TestContainerManager(unittest.TestCase):
    
    def setUp(self):
        # Mock config manager with current structure
        self.mock_config = Mock(spec=ConfigManager)
        self.mock_config.get_containers.return_value = {
            "chain-ingress": {
                "description": "VXLAN packet reception",
                "dockerfile": "src/containers/ingress/Dockerfile.ingress",
                "config_script": "ingress-config.sh",
                "interfaces": [
                    {
                        "name": "eth0",
                        "network": "external-ingress",
                        "ip": {"address": "172.20.0.10", "mask": 24}
                    },
                    {
                        "name": "eth1", 
                        "network": "ingress-vxlan",
                        "ip": {"address": "172.20.1.10", "mask": 24}
                    }
                ]
            },
            "chain-gcp": {
                "description": "GCP destination endpoint",
                "dockerfile": "src/containers/Dockerfile.base",
                "config_script": "gcp-config.sh",
                "interfaces": [
                    {
                        "name": "eth0",
                        "network": "fragment-gcp", 
                        "ip": {"address": "172.20.5.20", "mask": 24}
                    }
                ]
            }
        }
        
        self.mock_config.get_networks.return_value = [
            {"name": "external-ingress", "subnet": "172.20.0.0/24", "gateway": "172.20.0.1"},
            {"name": "fragment-gcp", "subnet": "172.20.5.0/24", "gateway": "172.20.5.1"}
        ]
        
        self.container_manager = ContainerManager(self.mock_config)
    
    def test_container_definitions(self):
        """Test that container definitions are properly configured"""
        containers = self.mock_config.get_containers()
        self.assertEqual(len(containers), 2)  # Test subset
        
        # Check ingress container
        self.assertIn('chain-ingress', containers)
        ingress = containers['chain-ingress'] 
        self.assertEqual(ingress['description'], 'VXLAN packet reception')
        self.assertEqual(ingress['interfaces'][0]['ip']['address'], '172.20.0.10')
    
    def test_container_network_mapping(self):
        """Test that network mappings are correct"""
        containers = self.mock_config.get_containers()
        
        for container_name, container in containers.items():
            self.assertIn('interfaces', container)
            
            # Each interface should have network and IP
            for interface in container['interfaces']:
                self.assertIn('network', interface)
                self.assertIn('ip', interface)
                self.assertIn('address', interface['ip'])
                self.assertIn('mask', interface['ip'])
    
    @patch('subprocess.run')
    def test_build_images_success(self, mock_run):
        """Test successful image building"""
        mock_run.return_value = Mock(returncode=0, stdout="success", stderr="")
        
        result = self.container_manager.build_images()
        self.assertTrue(result)
        
        # Should call docker build for base + specialized images
        self.assertGreaterEqual(mock_run.call_count, 1)
    
    @patch('subprocess.run')
    def test_start_containers_success(self, mock_run):
        """Test successful container startup"""
        mock_run.return_value = Mock(returncode=0, stdout="success", stderr="")
        
        with patch('time.sleep'):  # Mock sleep to speed up test
            result = self.container_manager.start_containers()
            self.assertTrue(result)
    
    def test_config_script_reference(self):
        """Test that config_script field is used correctly"""
        containers = self.mock_config.get_containers()
        
        for container_name, container in containers.items():
            self.assertIn('config_script', container)
            # Should end with .sh
            self.assertTrue(container['config_script'].endswith('.sh'))

if __name__ == '__main__':
    unittest.main()