"""
Network Management for VPP Multi-Container Chain

Handles Docker networks, connectivity testing, and network verification.
"""

import subprocess
import socket
import time
from .logger import get_logger, log_success, log_error, log_warning, log_info
from .config_manager import ConfigManager

class NetworkManager:
    """Manages Docker networks for the VPP chain"""
    
    def __init__(self, config_manager: ConfigManager):
        self.logger = get_logger()
        self.config_manager = config_manager
        self.NETWORKS = self.config_manager.get_networks()
        self.CONNECTIVITY_TESTS = self.config_manager.get_connectivity_tests()
    
    def setup_networks(self):
        """Create Docker networks for the chain"""
        try:
            log_info("Setting up Docker networks...")
            
            for network in self.NETWORKS:
                log_info(f"Creating network {network['name']} ({network['description']})")
                
                # Remove existing network if it exists
                subprocess.run([
                    "docker", "network", "rm", network["name"]
                ], capture_output=True, text=True)
                
                # Create new network
                result = subprocess.run([
                    "docker", "network", "create",
                    "--driver", "bridge",
                    "--subnet", network["subnet"],
                    "--gateway", network["gateway"],
                    network["name"]
                ], capture_output=True, text=True, check=True)
                
                log_success(f"Network {network['name']} created")
            
            log_success("All networks created successfully")
            return True
            
        except subprocess.CalledProcessError as e:
            log_error(f"Failed to create networks: {e.stderr}")
            return False
        except Exception as e:
            log_error(f"Network setup failed: {e}")
            return False
    
    def cleanup_networks(self):
        """Remove all Docker networks related to the project."""
        try:
            log_info("Cleaning up Docker networks...")

            # Remove networks defined in config
            for network in self.NETWORKS:
                try:
                    subprocess.run(["docker", "network", "rm", network["name"]], capture_output=True, text=True)
                    log_success(f"Network {network['name']} removed.")
                except Exception:
                    log_warning(f"Failed to remove network {network['name']} (may not exist or in use).")

            # Remove any networks matching the project's docker-compose naming convention
            # This is a fallback for networks created by docker-compose previously
            project_network_prefix = "ingress_vxlan_nat_ipsec_fragment_egress_"
            result = subprocess.run(["docker", "network", "ls", "--format", "{{.Name}}"], capture_output=True, text=True, check=True)
            all_networks = result.stdout.strip().split('\n')

            for net_name in all_networks:
                if net_name.startswith(project_network_prefix):
                    try:
                        subprocess.run(["docker", "network", "rm", net_name], capture_output=True, text=True)
                        log_success(f"Orphaned network {net_name} removed.")
                    except Exception:
                        log_warning(f"Failed to remove orphaned network {net_name} (may be in use).")

            # Clean up orphaned networks (general Docker prune)
            subprocess.run(["docker", "network", "prune", "-f"], capture_output=True, text=True)

            log_success("Network cleanup completed.")
            return True

        except Exception as e:
            log_error(f"Network cleanup failed: {e}")
            return False
    
    def verify_connectivity(self):
        """Verify basic network connectivity"""
        try:
            log_info("Verifying network connectivity...")
            
            # Test bridge connectivity from host
            log_info("Testing host → container connectivity...")
            
            # Get IP of chain-ingress from config_manager
            containers = self.config_manager.get_containers()
            ingress_ip = containers[0]["networks"]["underlay"] # Assuming ingress is the first container and has underlay network

            if not ingress_ip:
                log_error("Could not determine IP for chain-ingress")
                return False

            result = subprocess.run([
                "ping", "-c", "1", "-W", "2", ingress_ip
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                log_success(f"Host can reach ingress container ({ingress_ip})")
            else:
                log_error("Host cannot reach ingress container")
                return False
            
            log_success("Basic connectivity verified")
            return True
            
        except Exception as e:
            log_error(f"Connectivity verification failed: {e}")
            return False
    
    def test_connectivity(self):
        """Test inter-container connectivity"""
        try:
            log_info("Testing inter-container connectivity...")
            
            all_tests_passed = True
            
            for test in self.CONNECTIVITY_TESTS:
                log_info(f"Testing {test['description']}...")
                
                try:
                    result = subprocess.run([
                        "docker", "exec", test["from"],
                        "ping", "-c", "1", "-W", "2", test["to"]
                    ], capture_output=True, text=True, timeout=10)
                    
                    if result.returncode == 0:
                        log_success(f"{test['description']}: ✅ Connected")
                    else:
                        log_error(f"{test['description']}: ❌ Failed")
                        all_tests_passed = False
                        
                except subprocess.TimeoutExpired:
                    log_error(f"{test['description']}: ❌ Timeout")
                    all_tests_passed = False
                except Exception as e:
                    log_error(f"{test['description']}: ❌ Error: {e}")
                    all_tests_passed = False
            
            if all_tests_passed:
                log_success("All connectivity tests passed")
            else:
                log_error("Some connectivity tests failed")
            
            return all_tests_passed
            
        except Exception as e:
            log_error(f"Connectivity testing failed: {e}")
            return False
    
    def show_network_status(self):
        """Show current network status"""
        try:
            print("\n🌐 Network Status:")
            print("-" * 60)
            
            # Show Docker networks
            result = subprocess.run([
                "docker", "network", "ls", "--format", 
                "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
            ], capture_output=True, text=True, check=True)
            
            print(result.stdout)
            
            # Show network details for chain networks
            for network in self.NETWORKS:
                try:
                    result = subprocess.run([
                        "docker", "network", "inspect", network["name"],
                        "--format", "{{.IPAM.Config}}"
                    ], capture_output=True, text=True)
                    
                    if result.returncode == 0:
                        print(f"\n📡 {network['name']}: {network['subnet']} - {network['description']}")
                    else:
                        print(f"\n❌ {network['name']}: Not found")
                        
                except Exception:
                    print(f"\n❌ {network['name']}: Error getting details")
            
            return True
            
        except Exception as e:
            log_error(f"Network status display failed: {e}")
            return False
    
    def diagnose_connectivity_issues(self):
        """Diagnose and report connectivity issues"""
        try:
            log_info("Diagnosing connectivity issues...")
            
            issues_found = []
            
            # Check if all networks exist
            result = subprocess.run([
                "docker", "network", "ls", "--format", "{{.Name}}"
            ], capture_output=True, text=True, check=True)
            
            existing_networks = set(result.stdout.strip().split('\n'))
            
            for network in self.NETWORKS:
                if network["name"] not in existing_networks:
                    issues_found.append(f"Missing network: {network['name']}")
            
            # Check container network assignments
            containers = self.config_manager.get_containers()
            
            for container_info in containers:
                container_name = container_info["name"]
                try:
                    result = subprocess.run([
                        "docker", "inspect", container_name, 
                        "--format", "{{.NetworkSettings.Networks}}"
                    ], capture_output=True, text=True)
                    
                    if result.returncode != 0:
                        issues_found.append(f"Container {container_name} not found or inspect failed")
                        
                except Exception:
                    issues_found.append(f"Cannot inspect container {container_name}")
            
            # Report findings
            if issues_found:
                log_error("Connectivity issues found:")
                for issue in issues_found:
                    print(f"   ❌ {issue}")
                return False
            else:
                log_success("No connectivity issues detected")
                return True
                
        except Exception as e:
            log_error(f"Connectivity diagnosis failed: {e}")
            return False
    
    def test_port_connectivity(self, host, port, timeout=5):
        """Test if a specific port is reachable"""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((host, port))
            sock.close()
            return result == 0
        except Exception:
            return False
    
    def get_container_ip(self, container_name, network_name):
        """Get IP address of a container on a specific network"""
        try:
            result = subprocess.run([
                "docker", "inspect", container_name,
                "--format", f"{{{{.NetworkSettings.Networks.{network_name}.IPAddress}}}}"
            ], capture_output=True, text=True, check=True)
            
            ip = result.stdout.strip()
            return ip if ip else None
            
        except Exception:
            return None