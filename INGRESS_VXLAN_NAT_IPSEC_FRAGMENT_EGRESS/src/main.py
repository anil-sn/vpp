#!/usr/bin/env python3
"""
VPP Multi-Container Chain Management System

This is the main entry point for managing VPP multi-container chains.
It provides a unified interface for setup, testing, debugging, and cleanup operations.

Author: Claude Code
Version: 1.0.0
"""

import sys
import os
import argparse
import subprocess
from pathlib import Path

# Add src directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))

from utils.logger import setup_logger, log
from utils.container_manager import ContainerManager
from utils.network_manager import NetworkManager
from utils.traffic_generator import TrafficGenerator

class VPPChainManager:
    """Main manager for VPP multi-container chain operations"""
    
    def __init__(self):
        self.logger = setup_logger("vpp_chain")
        self.container_manager = ContainerManager()
        self.network_manager = NetworkManager()
        self.traffic_generator = TrafficGenerator()
        
    def setup(self, force_rebuild=False):
        """Setup the multi-container chain environment"""
        log.info("Starting VPP multi-container chain setup")
        
        try:
            # Cleanup existing environment if needed
            if force_rebuild:
                self.cleanup()
            
            # Build container images
            log.info("Building container images...")
            if not self.container_manager.build_images():
                log.error("Failed to build container images")
                return False
            
            # Setup networks
            log.info("Setting up container networks...")
            if not self.network_manager.setup_networks():
                log.error("Failed to setup networks")
                return False
            
            # Start containers
            log.info("Starting containers...")
            if not self.container_manager.start_containers():
                log.error("Failed to start containers")
                return False
            
            # Apply VPP configurations
            log.info("Applying VPP configurations...")
            if not self.container_manager.apply_configs():
                log.error("Failed to apply VPP configurations")
                return False
            
            # Verify setup
            log.info("Verifying setup...")
            if not self.verify_setup():
                log.error("Setup verification failed")
                return False
            
            log.info("✅ VPP multi-container chain setup completed successfully!")
            self._print_chain_status()
            return True
            
        except Exception as e:
            log.error(f"Setup failed with exception: {e}")
            return False
    
    def cleanup(self):
        """Cleanup the multi-container chain environment"""
        log.info("Starting VPP multi-container chain cleanup")
        
        try:
            # Stop and remove containers
            self.container_manager.stop_containers()
            
            # Remove networks
            self.network_manager.cleanup_networks()
            
            # Optional: Remove images
            self.container_manager.cleanup_images()
            
            log.info("✅ VPP multi-container chain cleanup completed!")
            return True
            
        except Exception as e:
            log.error(f"Cleanup failed with exception: {e}")
            return False
    
    def test(self, test_type="full"):
        """Run tests on the multi-container chain"""
        log.info(f"Starting {test_type} test suite")
        
        try:
            if not self.verify_setup():
                log.error("Environment not ready for testing")
                return False
            
            if test_type == "connectivity":
                return self._test_connectivity()
            elif test_type == "traffic":
                return self.traffic_generator.run_traffic_test()
            elif test_type == "full":
                return self._test_connectivity() and self.traffic_generator.run_traffic_test()
            else:
                log.error(f"Unknown test type: {test_type}")
                return False
                
        except Exception as e:
            log.error(f"Testing failed with exception: {e}")
            return False
    
    def debug(self, container, command):
        """Debug a specific container with a VPP command"""
        return self.container_manager.debug_container(container, command)
    
    def status(self):
        """Show current status of the chain"""
        self._print_chain_status()
        return self.container_manager.show_status()
    
    def monitor(self, duration=60):
        """Monitor the chain for a specified duration"""
        log.info(f"Monitoring chain for {duration} seconds...")
        return self.container_manager.monitor_chain(duration)
    
    def verify_setup(self):
        """Verify that the setup is correct and ready for operation"""
        log.info("Verifying VPP multi-container chain setup")
        
        # Check container status
        if not self.container_manager.verify_containers():
            return False
        
        # Check VPP responsiveness
        if not self.container_manager.verify_vpp():
            return False
        
        # Check network connectivity
        if not self.network_manager.verify_connectivity():
            return False
        
        log.info("✅ Setup verification completed successfully")
        return True
    
    def _test_connectivity(self):
        """Test inter-container connectivity"""
        log.info("Testing inter-container connectivity")
        return self.network_manager.test_connectivity()
    
    def _print_chain_status(self):
        """Print the current chain topology and status"""
        print("\n🔗 VPP Multi-Container Chain Topology:")
        print("┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐")
        print("│   INGRESS   │───▶│   VXLAN     │───▶│    NAT44    │───▶│   IPSEC     │───▶│ FRAGMENT    │───▶ [GCP]")
        print("│ 192.168.1.2 │    │ Decap VNI   │    │ 10.10.10.10 │    │ AES-GCM-128 │    │  MTU 1400   │")
        print("│             │    │    100      │    │ → 10.0.3.1  │    │ Encryption  │    │ IP Fragments│")
        print("└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘")
        print("        ▲                    │                    │                    │                    │")
        print("        │              VXLAN Decap         NAT Translation      IPsec ESP           IP Fragmentation")
        print("        │")
        print("┌─────────────┐")
        print("│   Traffic   │")
        print("│ Generator   │")
        print("│  (Python)   │")
        print("└─────────────┘")
        print()

def main():
    parser = argparse.ArgumentParser(
        description="VPP Multi-Container Chain Management System",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 main.py setup                    # Setup the chain environment
  python3 main.py setup --force            # Force rebuild and setup
  python3 main.py test                     # Run full test suite
  python3 main.py test --type connectivity # Test only connectivity
  python3 main.py debug chain-nat "show nat44 sessions"
  python3 main.py status                   # Show chain status
  python3 main.py monitor --duration 120   # Monitor for 2 minutes
  python3 main.py cleanup                  # Cleanup environment
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Setup command
    setup_parser = subparsers.add_parser('setup', help='Setup the multi-container chain')
    setup_parser.add_argument('--force', action='store_true', help='Force rebuild existing setup')
    
    # Test command
    test_parser = subparsers.add_parser('test', help='Run tests on the chain')
    test_parser.add_argument('--type', choices=['connectivity', 'traffic', 'full'], 
                           default='full', help='Type of test to run')
    
    # Debug command
    debug_parser = subparsers.add_parser('debug', help='Debug a specific container')
    debug_parser.add_argument('container', help='Container name to debug')
    debug_parser.add_argument('command', help='VPP command to execute')
    
    # Status command
    subparsers.add_parser('status', help='Show current chain status')
    
    # Monitor command
    monitor_parser = subparsers.add_parser('monitor', help='Monitor the chain')
    monitor_parser.add_argument('--duration', type=int, default=60, 
                               help='Monitoring duration in seconds')
    
    # Cleanup command
    subparsers.add_parser('cleanup', help='Cleanup the chain environment')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    # Check root privileges for most operations
    if args.command in ['setup', 'cleanup', 'test'] and os.geteuid() != 0:
        print("❌ This command must be run as root or with sudo")
        print("   Usage: sudo python3 main.py", args.command)
        return 1
    
    # Create manager instance
    manager = VPPChainManager()
    
    # Execute command
    try:
        if args.command == 'setup':
            success = manager.setup(force_rebuild=args.force)
        elif args.command == 'test':
            success = manager.test(test_type=args.type)
        elif args.command == 'debug':
            success = manager.debug(args.container, args.command)
        elif args.command == 'status':
            success = manager.status()
        elif args.command == 'monitor':
            success = manager.monitor(duration=args.duration)
        elif args.command == 'cleanup':
            success = manager.cleanup()
        else:
            print(f"Unknown command: {args.command}")
            return 1
        
        return 0 if success else 1
        
    except KeyboardInterrupt:
        print("\n🛑 Operation interrupted by user")
        return 1
    except Exception as e:
        print(f"❌ Operation failed: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())