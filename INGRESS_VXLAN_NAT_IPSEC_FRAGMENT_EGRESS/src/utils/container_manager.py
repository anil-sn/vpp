"""
Container Management for VPP Multi-Container Chain

Handles Docker container lifecycle, VPP configuration, and debugging operations.
"""

import subprocess
import time
import json
from pathlib import Path
from .logger import get_logger, log_success, log_error, log_warning, log_info

class ContainerManager:
    """Manages Docker containers in the VPP chain"""
    
    # Container definitions
    CONTAINERS = [
        {
            "name": "chain-ingress",
            "description": "VXLAN packet reception",
            "config": "ingress-config.sh",
            "networks": ["underlay", "chain-1-2"],
            "ip_addresses": {"underlay": "192.168.1.2", "chain-1-2": "10.1.1.1"}
        },
        {
            "name": "chain-vxlan",
            "description": "VXLAN decapsulation",
            "config": "vxlan-config.sh", 
            "networks": ["chain-1-2", "chain-2-3"],
            "ip_addresses": {"chain-1-2": "10.1.1.2", "chain-2-3": "10.1.2.1"}
        },
        {
            "name": "chain-nat",
            "description": "NAT44 translation",
            "config": "nat-config.sh",
            "networks": ["chain-2-3", "chain-3-4"],
            "ip_addresses": {"chain-2-3": "10.1.2.2", "chain-3-4": "10.1.3.1"}
        },
        {
            "name": "chain-ipsec", 
            "description": "IPsec encryption",
            "config": "ipsec-config.sh",
            "networks": ["chain-3-4", "chain-4-5"],
            "ip_addresses": {"chain-3-4": "10.1.3.2", "chain-4-5": "10.1.4.1"}
        },
        {
            "name": "chain-fragment",
            "description": "IP fragmentation", 
            "config": "fragment-config.sh",
            "networks": ["chain-4-5", "underlay"],
            "ip_addresses": {"chain-4-5": "10.1.4.2", "underlay": "192.168.1.4"}
        },
        {
            "name": "chain-gcp",
            "description": "GCP destination endpoint",
            "config": "gcp-config.sh",
            "networks": ["underlay"],
            "ip_addresses": {"underlay": "192.168.1.3"}
        }
    ]
    
    def __init__(self):
        self.logger = get_logger()
        self.project_root = Path(__file__).parent.parent.parent
        
    def build_images(self):
        """Build container images"""
        try:
            log_info("Building VPP chain base image...")
            
            dockerfile_path = self.project_root / "src" / "containers" / "Dockerfile.base"
            
            # Build base image
            result = subprocess.run([
                "docker", "build", 
                "-t", "vpp-chain-base:latest",
                "-f", str(dockerfile_path),
                str(self.project_root)
            ], capture_output=True, text=True, check=True)
            
            log_success("Container images built successfully")
            return True
            
        except subprocess.CalledProcessError as e:
            log_error(f"Failed to build images: {e.stderr}")
            return False
        except Exception as e:
            log_error(f"Image build failed: {e}")
            return False
    
    def start_containers(self):
        """Start all containers using docker-compose"""
        try:
            log_info("Starting container chain...")
            
            compose_file = self.project_root / "docker-compose.yml"
            
            # Start containers
            result = subprocess.run([
                "docker-compose", "-f", str(compose_file),
                "up", "-d"
            ], capture_output=True, text=True, check=True)
            
            # Wait for containers to initialize
            log_info("Waiting for containers to initialize...")
            time.sleep(15)
            
            log_success("Containers started successfully")
            return True
            
        except subprocess.CalledProcessError as e:
            log_error(f"Failed to start containers: {e.stderr}")
            return False
        except Exception as e:
            log_error(f"Container startup failed: {e}")
            return False
    
    def stop_containers(self):
        """Stop and remove all containers"""
        try:
            log_info("Stopping container chain...")
            
            compose_file = self.project_root / "docker-compose.yml"
            
            # Stop containers
            subprocess.run([
                "docker-compose", "-f", str(compose_file),
                "down", "--volumes", "--remove-orphans"
            ], capture_output=True, text=True)
            
            # Force remove any remaining containers
            for container in self.CONTAINERS:
                try:
                    subprocess.run([
                        "docker", "rm", "-f", container["name"]
                    ], capture_output=True, text=True)
                except:
                    pass
            
            log_success("Containers stopped successfully")
            return True
            
        except Exception as e:
            log_error(f"Container cleanup failed: {e}")
            return False
    
    def apply_configs(self):
        """Apply VPP configurations to all containers"""
        try:
            log_info("Applying VPP configurations...")
            
            # Wait a bit more for VPP to fully initialize
            time.sleep(5)
            
            for container in self.CONTAINERS:
                log_info(f"Configuring {container['name']} ({container['description']})...")
                
                # Execute configuration script in container
                result = subprocess.run([
                    "docker", "exec", container["name"],
                    "bash", "-c", f"cd /vpp-config && ./{container['config']}"
                ], capture_output=True, text=True)
                
                if result.returncode != 0:
                    log_error(f"Configuration failed for {container['name']}: {result.stderr}")
                    return False
                
                log_success(f"{container['name']} configured successfully")
            
            log_success("All VPP configurations applied successfully")
            return True
            
        except Exception as e:
            log_error(f"Configuration application failed: {e}")
            return False
    
    def verify_containers(self):
        """Verify that all containers are running"""
        try:
            log_info("Verifying container status...")
            
            # Get list of running containers
            result = subprocess.run([
                "docker", "ps", "--format", "{{.Names}}"
            ], capture_output=True, text=True, check=True)
            
            running_containers = set(result.stdout.strip().split('\n'))
            
            all_running = True
            for container in self.CONTAINERS:
                if container["name"] in running_containers:
                    log_success(f"Container {container['name']} is running")
                else:
                    log_error(f"Container {container['name']} is not running")
                    all_running = False
            
            return all_running
            
        except Exception as e:
            log_error(f"Container verification failed: {e}")
            return False
    
    def verify_vpp(self):
        """Verify that VPP is responsive in all containers"""
        try:
            log_info("Verifying VPP responsiveness...")
            
            all_responsive = True
            for container in self.CONTAINERS:
                try:
                    result = subprocess.run([
                        "docker", "exec", container["name"], 
                        "vppctl", "show", "version"
                    ], capture_output=True, text=True, timeout=10)
                    
                    if result.returncode == 0:
                        log_success(f"VPP responsive in {container['name']}")
                    else:
                        log_error(f"VPP not responsive in {container['name']}")
                        all_responsive = False
                        
                except subprocess.TimeoutExpired:
                    log_error(f"VPP timeout in {container['name']}")
                    all_responsive = False
                except Exception as e:
                    log_error(f"VPP check failed for {container['name']}: {e}")
                    all_responsive = False
            
            return all_responsive
            
        except Exception as e:
            log_error(f"VPP verification failed: {e}")
            return False
    
    def debug_container(self, container_name, command):
        """Execute a VPP command in a specific container for debugging"""
        try:
            # Validate container name
            valid_containers = [c["name"] for c in self.CONTAINERS]
            if container_name not in valid_containers:
                log_error(f"Invalid container name: {container_name}")
                log_info(f"Valid containers: {', '.join(valid_containers)}")
                return False
            
            log_info(f"Executing 'vppctl {command}' in {container_name}")
            
            # Execute command
            result = subprocess.run([
                "docker", "exec", container_name, "vppctl", command
            ], text=True, timeout=30)
            
            if result.returncode == 0:
                log_success(f"Command executed successfully in {container_name}")
                return True
            else:
                log_error(f"Command failed in {container_name}")
                return False
                
        except subprocess.TimeoutExpired:
            log_error(f"Command timeout in {container_name}")
            return False
        except Exception as e:
            log_error(f"Debug command failed: {e}")
            return False
    
    def show_status(self):
        """Show detailed status of all containers"""
        try:
            print("\n🐳 Container Status:")
            print("-" * 80)
            
            for container in self.CONTAINERS:
                print(f"\n📦 {container['name']} ({container['description']})")
                
                # Check if running
                try:
                    result = subprocess.run([
                        "docker", "ps", "--filter", f"name={container['name']}",
                        "--format", "{{.Status}}"
                    ], capture_output=True, text=True)
                    
                    if result.stdout.strip():
                        print(f"   Status: 🟢 Running ({result.stdout.strip()})")
                        
                        # Get VPP interface stats
                        try:
                            vpp_result = subprocess.run([
                                "docker", "exec", container["name"], 
                                "vppctl", "show", "interface"
                            ], capture_output=True, text=True, timeout=5)
                            
                            if vpp_result.returncode == 0:
                                # Parse packet counts
                                lines = vpp_result.stdout.split('\n')
                                for line in lines:
                                    if 'rx packets' in line:
                                        try:
                                            packets = int(line.split()[-1])
                                            print(f"   RX Packets: {packets}")
                                            break
                                        except:
                                            pass
                            else:
                                print(f"   VPP: ❌ Not responsive")
                        except:
                            print(f"   VPP: ⚠️ Status unknown")
                            
                    else:
                        print(f"   Status: 🔴 Not running")
                        
                except Exception as e:
                    print(f"   Status: ❌ Error checking status")
            
            return True
            
        except Exception as e:
            log_error(f"Status display failed: {e}")
            return False
    
    def monitor_chain(self, duration):
        """Monitor the chain for a specified duration"""
        try:
            log_info(f"Starting chain monitoring for {duration} seconds...")
            
            start_time = time.time()
            
            while time.time() - start_time < duration:
                print(f"\n⏱️ Monitoring... ({int(time.time() - start_time)}/{duration}s)")
                
                # Quick status check
                for container in self.CONTAINERS[:3]:  # Monitor first 3 containers
                    try:
                        result = subprocess.run([
                            "docker", "exec", container["name"],
                            "vppctl", "show", "interface"
                        ], capture_output=True, text=True, timeout=5)
                        
                        if result.returncode == 0:
                            print(f"   {container['name']}: ✅ Active")
                        else:
                            print(f"   {container['name']}: ❌ Issue")
                    except:
                        print(f"   {container['name']}: ⚠️ Timeout")
                
                time.sleep(10)  # Update every 10 seconds
            
            log_success("Monitoring completed")
            return True
            
        except KeyboardInterrupt:
            log_info("Monitoring interrupted by user")
            return True
        except Exception as e:
            log_error(f"Monitoring failed: {e}")
            return False
    
    def cleanup_images(self, force=False):
        """Clean up container images"""
        try:
            if not force:
                response = input("Remove container images? (y/N): ").lower()
                if response not in ['y', 'yes']:
                    return True
            
            log_info("Cleaning up container images...")
            
            # Remove chain images
            subprocess.run([
                "docker", "image", "rm", "vpp-chain-base:latest"
            ], capture_output=True, text=True)
            
            # System cleanup
            subprocess.run([
                "docker", "system", "prune", "-f"
            ], capture_output=True, text=True)
            
            log_success("Container images cleaned up")
            return True
            
        except Exception as e:
            log_error(f"Image cleanup failed: {e}")
            return False