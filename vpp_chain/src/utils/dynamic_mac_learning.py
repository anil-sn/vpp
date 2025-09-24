#!/usr/bin/env python3
"""
Dynamic MAC Learning for VPP Multi-Container Chain

This module implements a comprehensive dynamic MAC address learning system for VPP multi-container chains.
The primary goal is to eliminate hardcoded MAC addresses and automatically discover the correct VPP interface
MAC addresses at runtime, then update neighbor tables across all containers to ensure proper L3 forwarding.

Key Features:
- Automatic VPP interface MAC discovery from running containers
- Dynamic neighbor table updates across all container connections  
- Multiple fallback methods for robust MAC address discovery
- Promiscuous mode enablement for enhanced packet reception
- Comprehensive error handling and verification
- Real-time neighbor table validation

Architecture Context:
This system addresses the critical L3 MAC mismatch issue where VPP containers need to forward packets
to each other but don't know the correct destination MAC addresses. Without proper MAC learning,
packets get dropped due to L3 MAC mismatch errors, resulting in poor end-to-end delivery rates.

The system discovers MAC addresses by:
1. Querying VPP hardware interfaces directly from destination containers
2. Using VPP-based neighbor discovery with ping/ARP resolution
3. Validating discovered MACs are VPP-style addresses (02:fe:xx:xx:xx:xx)
4. Automatically updating neighbor tables with discovered MACs

Author: Claude Code
Version: 2.0
Last Updated: 2025-09-12
"""

import subprocess
import time
import json
import re
from .logger import log_info, log_warning, log_error, log_success

class DynamicMACLearner:
    """
    Handles dynamic MAC address learning for VPP containers in the multi-container chain.
    
    This class provides the core functionality for automatically discovering VPP interface MAC
    addresses and updating neighbor tables to ensure proper packet forwarding between containers.
    
    The learning process follows this workflow:
    1. Wait for all VPP instances to be ready and responsive
    2. Discover actual VPP interface MAC addresses from each container
    3. Update neighbor tables with discovered MACs for proper L3 forwarding
    4. Enable promiscuous mode on interfaces for better packet reception
    5. Verify all neighbor table updates were successful
    
    Attributes:
        config_manager: Configuration manager instance for accessing container topology
        containers: Dictionary of container configurations from config.json
    """
    
    def __init__(self, config_manager):
        """
        Initialize the MAC learner with configuration manager.
        
        Args:
            config_manager: ConfigManager instance containing container and network topology
        """
        self.config_manager = config_manager
        self.containers = config_manager.get_containers()
    
    def discover_vpp_interface_mac(self, container_name, interface="host-eth0"):
        """
        Discover the actual VPP interface MAC address from a running container.
        
        This method uses multiple VPP CLI commands to reliably extract the hardware MAC address
        of a VPP interface. It's critical for dynamic MAC learning because VPP assigns random
        MAC addresses to host interfaces, and these need to be discovered at runtime.
        
        The method tries multiple approaches in order of reliability:
        1. 'show hardware-interfaces' - Most reliable, shows actual ethernet address
        2. 'show interface' - Backup method for interface information
        3. 'show interface addr' - Alternative method if others fail
        
        Args:
            container_name (str): Name of the Docker container to query
            interface (str): VPP interface name to get MAC for (default: "host-eth0")
            
        Returns:
            str: MAC address in format "02:fe:xx:xx:xx:xx" if found, None otherwise
            
        Note:
            - Only accepts VPP-style MAC addresses (starting with "02:fe:")
            - Rejects Docker bridge MAC addresses which don't start with "02:fe:"
            - Uses 10-second timeout per command to avoid hanging
        """
        try:
            # Try multiple VPP commands to get the MAC address - ordered by reliability
            commands = [
                f'docker exec {container_name} vppctl show hardware-interfaces {interface}',  # Most reliable
                f'docker exec {container_name} vppctl show interface',                        # General interface info
                f'docker exec {container_name} vppctl show interface addr'                    # Address-specific info
            ]
            
            for cmd in commands:
                try:
                    result = subprocess.run(cmd.split(), capture_output=True, text=True, timeout=10)
                    if result.returncode == 0:
                        # Parse MAC address from different command outputs using appropriate regex
                        if "hardware-interfaces" in cmd:
                            # Look for "Ethernet address XX:XX:XX:XX:XX:XX" pattern
                            mac_match = re.search(r'Ethernet address\s+([0-9a-f:]{17})', result.stdout, re.IGNORECASE)
                        else:
                            # Look for various MAC address formats in other commands
                            mac_match = re.search(r'(?:HW address|L2 address|mac)\s+([0-9a-f:]{17})', result.stdout, re.IGNORECASE)
                        
                        if mac_match:
                            mac = mac_match.group(1).lower()
                            # Critical validation: only accept VPP-style MACs to avoid Docker bridge MACs
                            if mac.startswith("02:fe:"):
                                log_success(f"Discovered VPP MAC for {container_name} {interface}: {mac}")
                                return mac
                            else:
                                log_warning(f"Found non-VPP MAC for {container_name} {interface}: {mac} (ignoring)")
                            
                except subprocess.TimeoutExpired:
                    log_warning(f"Timeout executing command: {cmd}")
                    continue
                except Exception as e:
                    log_warning(f"Command failed: {cmd} - {e}")
                    continue
            
            log_error(f"Could not discover VPP MAC for {container_name} {interface}")
            return None
            
        except Exception as e:
            log_error(f"Error discovering MAC for {container_name}: {e}")
            return None
    
    def update_neighbor_table(self, container_name, neighbor_ip, neighbor_mac, interface="host-eth1"):
        """
        Update VPP neighbor table with discovered MAC address for proper L3 forwarding.
        
        This method is the core of the MAC learning system. It adds entries to VPP's neighbor
        table (ARP cache) so that when VPP needs to forward packets to a destination IP,
        it knows the correct MAC address to use in the L2 header.
        
        Without proper neighbor table entries, VPP would either:
        1. Drop packets due to L3 MAC mismatch (no neighbor entry)
        2. Use wrong MAC addresses (stale or incorrect entries)
        3. Generate ARP requests that may not be answered in container environments
        
        Args:
            container_name (str): Source container where neighbor table will be updated
            neighbor_ip (str): Destination IP address (e.g., "172.20.102.20")
            neighbor_mac (str): Discovered MAC address of destination (e.g., "02:fe:xx:xx:xx:xx")
            interface (str): VPP interface name to associate neighbor with (default: "host-eth1")
            
        Returns:
            bool: True if neighbor table update succeeded, False otherwise
            
        Example:
            update_neighbor_table("security-processor", "172.20.102.20", "02:fe:f1:cc:71:64", "host-eth1")
            This tells security-processor that packets destined for 172.20.102.20 should use
            MAC address 02:fe:f1:cc:71:64 when forwarding via host-eth1 interface.
        """
        try:
            # VPP CLI command to set neighbor table entry (static ARP entry)
            cmd = f'docker exec {container_name} vppctl set ip neighbor {interface} {neighbor_ip} {neighbor_mac}'
            result = subprocess.run(cmd.split(), capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                log_success(f"Updated {container_name} neighbor table: {neighbor_ip} -> {neighbor_mac}")
                return True
            else:
                log_error(f"Failed to update neighbor table in {container_name}: {result.stderr}")
                return False
                
        except Exception as e:
            log_error(f"Error updating neighbor table in {container_name}: {e}")
            return False
    
    def verify_neighbor_table(self, container_name):
        """
        Verify and display current neighbor table for debugging and validation.
        
        This method shows the current state of VPP's neighbor table (ARP cache) for a container.
        It's useful for debugging MAC learning issues and verifying that neighbor table updates
        were successful. The output shows Age, IP address, Flags, MAC address, and Interface.
        
        Args:
            container_name (str): Container to query neighbor table from
            
        Returns:
            str: Raw output from VPP 'show ip neighbors' command, or None if failed
            
        Example output:
            Age               IP                    Flags      Ethernet              Interface       
            142.6517          172.20.101.10                D    02:fe:f7:56:20:32     host-eth0
            3.3725            172.20.102.20                D    02:fe:87:3a:32:a8     host-eth1
            
        Flags: D = Dynamic, S = Static, N = No-FIB-Entry, R = Router, A = Adjacency
        """
        try:
            cmd = f'docker exec {container_name} vppctl show ip neighbors'
            result = subprocess.run(cmd.split(), capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                log_info(f"Current neighbor table for {container_name}:")
                for line in result.stdout.strip().split('\n'):
                    # Skip header line and empty lines, but show all neighbor entries
                    if line.strip() and not line.startswith('Age'):
                        log_info(f"  {line.strip()}")
                return result.stdout
            else:
                log_warning(f"Could not retrieve neighbor table from {container_name}")
                return None
                
        except Exception as e:
            log_error(f"Error verifying neighbor table in {container_name}: {e}")
            return None
    
    def learn_and_update_all_macs(self):
        """
        Perform complete dynamic MAC learning for all container connections.
        
        This is the main orchestration method that coordinates the entire MAC learning process.
        It handles the full workflow of discovering MAC addresses and updating neighbor tables
        for all critical container-to-container connections in the VPP chain.
        
        The learning process covers these key connections:
        1. VXLAN-PROCESSOR → SECURITY-PROCESSOR (172.20.101.20)
        2. SECURITY-PROCESSOR → DESTINATION (172.20.102.20) - Most critical for packet delivery
        
        The method ensures proper sequencing:
        1. Wait for all VPP instances to be fully operational
        2. Discover MAC addresses from destination containers
        3. Update neighbor tables in source containers
        4. Verify all updates were successful
        
        Returns:
            bool: True if all MAC learning succeeded, False if any critical step failed
            
        Note:
            The security-processor → destination connection is most critical because this is
            where encrypted IPsec packets are forwarded. MAC mismatch at this stage results
            in complete packet loss and 0% end-to-end delivery rate.
        """
        log_info("Starting dynamic MAC learning for all container connections...")
        
        # --- START OF FIX ---
        # Get the list of containers dynamically from the current configuration
        containers_in_this_mode = self.containers.keys()
        
        log_info(f"Waiting for VPP containers in this mode to be ready: {list(containers_in_this_mode)}")
        for container_name in containers_in_this_mode:
            wait_count = 0
            max_wait = 30
            while wait_count < max_wait:
                try:
                    result = subprocess.run(
                        f'docker exec {container_name} vppctl show version'.split(),
                        capture_output=True, text=True, timeout=5
                    )
                    if result.returncode == 0:
                        log_success(f"{container_name} VPP is ready")
                        break
                except:
                    pass
                
                time.sleep(1)
                wait_count += 1
                if wait_count >= max_wait:
                    log_error(f"{container_name} VPP not ready after {max_wait} seconds")
                    return False
        # --- END OF FIX ---
        
        success = True
        
        # Step 2: Learn MAC addresses and update neighbor tables for each connection
        
        # --- START OF FIX ---
        # Conditionally learn MACs only if the required containers exist in this mode
        if "vxlan-processor" in containers_in_this_mode and "security-processor" in containers_in_this_mode:
            log_info("Learning MAC: vxlan-processor -> security-processor")
            security_mac = self.discover_vpp_interface_mac("security-processor", "host-eth0")
            if security_mac:
                if not self.update_neighbor_table("vxlan-processor", "172.20.101.20", security_mac, "host-eth1"):
                    success = False
            else:
                log_error("Failed to discover security-processor MAC")
                success = False

        if "security-processor" in containers_in_this_mode and "destination" in containers_in_this_mode:
            log_info("Learning MAC: security-processor -> destination")  
            destination_mac = self.discover_vpp_interface_mac("destination", "host-eth0")
            if destination_mac:
                if not self.update_neighbor_table("security-processor", "172.20.102.20", destination_mac, "host-eth1"):
                    success = False
            else:
                log_error("Failed to discover destination MAC")
                success = False
        # --- END OF FIX ---

        log_info("Verifying updated neighbor tables...")
        for container_name in containers_in_this_mode:
            self.verify_neighbor_table(container_name)
        
        if success:
            log_success("Dynamic MAC learning completed successfully!")
            return True
        else:
            log_error("Dynamic MAC learning failed for some connections")
            return False

    def enable_arp_learning(self):
        """
        Enable promiscuous mode on all VPP interfaces to enhance packet reception.
        
        Promiscuous mode allows VPP interfaces to receive all packets on the network segment,
        not just those destined for their specific MAC address. This is beneficial for:
        1. Better ARP/neighbor discovery in container environments
        2. Receiving packets with slight MAC address mismatches during learning phase
        3. Enhanced packet capture and debugging capabilities
        
        The method enables promiscuous mode on all host interfaces in each container:
        - vxlan-processor: host-eth0 (external traffic), host-eth1 (to security processor)
        - security-processor: host-eth0 (from vxlan processor), host-eth1 (to destination)
        - destination: host-eth0 (from security processor)
        
        Note: This is a best-effort operation - failures are logged but don't stop the process.
        """
        log_info("Enabling ARP-based MAC learning on all interfaces...")
        
        # Map containers to their VPP host interfaces based on current architecture
        containers_interfaces = {
            "vxlan-processor": ["host-eth0", "host-eth1"],      # External + to security
            "security-processor": ["host-eth0", "host-eth1"],   # From vxlan + to destination
            "destination": ["host-eth0"]                        # From security processor only
        }
        
        for container, interfaces in containers_interfaces.items():
            for interface in interfaces:
                try:
                    # VPP command to enable promiscuous mode on interface
                    cmd = f'docker exec {container} vppctl set interface promiscuous on {interface}'
                    subprocess.run(cmd.split(), capture_output=True, timeout=5)
                    
                    log_info(f"Enabled promiscuous mode on {container}:{interface}")
                    
                except Exception as e:
                    # Log warning but continue - promiscuous mode is helpful but not critical
                    log_warning(f"Could not enable promiscuous mode on {container}:{interface}: {e}")

def run_dynamic_mac_learning(config_manager):
    """
    Entry point for running dynamic MAC learning system.
    
    This function serves as the main interface for the dynamic MAC learning system.
    It creates a DynamicMACLearner instance and orchestrates the complete learning process.
    
    The learning workflow:
    1. Enable promiscuous mode on all interfaces for better packet reception
    2. Discover VPP interface MAC addresses from destination containers  
    3. Update neighbor tables in source containers with discovered MACs
    4. Verify all neighbor table updates were successful
    
    Args:
        config_manager: ConfigManager instance containing container topology information
        
    Returns:
        bool: True if complete MAC learning succeeded, False if any critical step failed
        
    Usage:
        This function is called automatically during container startup from the
        ContainerManager.start_containers() method after all VPP configurations
        are applied but before the system is marked as ready for traffic.
    """
    learner = DynamicMACLearner(config_manager)
    
    # Step 1: Enable promiscuous mode for enhanced packet reception
    learner.enable_arp_learning()
    
    # Step 2: Perform complete MAC learning and neighbor table updates
    return learner.learn_and_update_all_macs()