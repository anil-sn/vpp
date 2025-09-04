#!/usr/bin/env python3
"""
Unit tests for ContainerManager
"""

import unittest
import sys
import os
from unittest.mock import Mock, patch, MagicMock

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from utils.container_manager import ContainerManager

class TestContainerManager(unittest.TestCase):
    
    def setUp(self):
        self.container_manager = ContainerManager()
    
    def test_container_definitions(self):
        """Test that container definitions are properly configured"""
        self.assertEqual(len(self.container_manager.CONTAINERS), 6)
        
        # Check ingress container
        ingress = self.container_manager.CONTAINERS[0]
        self.assertEqual(ingress['name'], 'chain-ingress')
        self.assertEqual(ingress['ip_addresses']['underlay'], '192.168.10.2')
        self.assertEqual(ingress['ip_addresses']['chain-1-2'], '10.1.1.1')
    
    def test_container_network_mapping(self):
        """Test that network mappings are correct"""
        for container in self.container_manager.CONTAINERS:
            self.assertIn('networks', container)
            self.assertIn('ip_addresses', container)
            
            # Each network should have corresponding IP
            for network in container['networks']:
                self.assertIn(network, container['ip_addresses'])
    
    @patch('subprocess.run')
    def test_build_images_success(self, mock_run):
        """Test successful image building"""
        mock_run.return_value = Mock(returncode=0, stdout="success", stderr="")
        
        result = self.container_manager.build_images()
        self.assertTrue(result)
        mock_run.assert_called_once()
    
    @patch('subprocess.run')
    def test_start_containers_success(self, mock_run):
        """Test successful container startup"""
        mock_run.return_value = Mock(returncode=0, stdout="success", stderr="")
        
        with patch('time.sleep'):  # Mock sleep to speed up test
            result = self.container_manager.start_containers()
            self.assertTrue(result)

if __name__ == '__main__':
    unittest.main()