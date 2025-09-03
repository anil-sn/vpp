"""
Network Management for VPP Multi-Container Chain

Handles Docker networks, connectivity testing, and network verification.
"""

import subprocess
import socket
import time
from .logger import get_logger, log_success, log_error, log_warning, log_info

class NetworkManager:
    """Manages Docker networks for the VPP chain"""
    
    # Network definitions
    NETWORKS = [
        {
            "name": "underlay",
            "subnet": "192.168.1.0/24",
            "gateway": "192.168.1.1",
            "description": "Main underlay network"
        },
        {
            "name": "chain-1-2", 
            "subnet": "10.1.1.0/24",
            "gateway": "10.1.1.1",
            "description": "Ingress → VXLAN"
        },
        {
            "name": "chain-2-3",
            "subnet": "10.1.2.0/24", 
            "gateway": "10.1.2.1",
            "description": "VXLAN → NAT"
        },
        {
            "name": "chain-3-4",
            "subnet": "10.1.3.0/24",
            "gateway": "10.1.3.1", 
            "description": "NAT → IPsec"
        },
        {
            "name": "chain-4-5",
            "subnet": "10.1.4.0/24",
            "gateway": "10.1.4.1",
            "description": "IPsec → Fragment"
        }
    ]
    
    # Connectivity test pairs
    CONNECTIVITY_TESTS = [
        {"from": "chain-ingress", "to": "10.1.1.2", "description": "Ingress → VXLAN"},
        {"from": "chain-vxlan", "to": "10.1.2.2", "description": "VXLAN → NAT"},
        {"from": "chain-nat", "to": "10.1.3.2", "description": "NAT → IPsec"},
        {"from": "chain-ipsec", "to": "10.1.4.2", "description": "IPsec → Fragment"},
        {"from": "chain-fragment", "to": "192.168.1.3", "description": "Fragment → GCP"}
    ]
    
    def __init__(self):
        self.logger = get_logger()
    
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
        """Remove all Docker networks"""
        try:
            log_info("Cleaning up Docker networks...")
            
            for network in self.NETWORKS:
                try:
                    subprocess.run([
                        "docker", "network", "rm", network["name"]
                    ], capture_output=True, text=True)
                    log_success(f"Network {network['name']} removed")
                except:
                    log_warning(f"Failed to remove network {network['name']} (may not exist)")
            
            # Clean up orphaned networks
            subprocess.run([
                "docker", "network", "prune", "-f"
            ], capture_output=True, text=True)
            
            log_success("Network cleanup completed")
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
            result = subprocess.run([
                "ping", "-c", "1", "-W", "2", "192.168.1.2"
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                log_success("Host can reach ingress container")
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
            containers = ["chain-ingress", "chain-vxlan", "chain-nat", "chain-ipsec", "chain-fragment", "chain-gcp"]
            
            for container in containers:
                try:
                    result = subprocess.run([
                        "docker", "inspect", container, 
                        "--format", "{{.NetworkSettings.Networks}}"
                    ], capture_output=True, text=True)
                    
                    if result.returncode != 0:
                        issues_found.append(f"Container {container} not found")
                        
                except Exception:
                    issues_found.append(f"Cannot inspect container {container}")
            
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