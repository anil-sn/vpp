"""
Container Management for VPP Multi-Container Chain

Handles Docker container lifecycle, VPP configuration, and debugging operations.
"""

import subprocess
import time
from pathlib import Path
import yaml # Added for dynamic docker-compose.yml generation
from .logger import get_logger, log_success, log_error, log_warning, log_info
from .config_manager import ConfigManager

class ContainerManager:
    """Manages Docker containers in the VPP chain"""
    
    def __init__(self, config_manager: ConfigManager):
        self.logger = get_logger()
        self.config_manager = config_manager
        self.project_root = Path(__file__).parent.parent.parent
        self.CONTAINERS = self.config_manager.get_containers()
        self.NETWORKS = self.config_manager.get_networks()

    def generate_docker_compose_file(self):
        """Generates the docker-compose.yml file based on the current configuration"""
        log_info("Generating docker-compose.yml...")
        compose_data = {
            "version": "3.8",
            "services": {},
            "networks": {},
            "volumes": {
                "vpp-logs": {"driver": "local"},
                "packet-captures": {"driver": "local"}
            }
        }

        # Add networks
        for net in self.NETWORKS:
            compose_data["networks"][net["name"]] = {
                "driver": "bridge",
                "ipam": {
                    "config": [
                        {"subnet": net["subnet"]}
                    ]
                }
            }
            if "gateway" in net:
                compose_data["networks"][net["name"]]["ipam"]["config"][0]["gateway"] = net["gateway"]

        # Add containers
        for container in self.CONTAINERS:
            service_name = container["name"]
            networks_config = {}
            for net_name, ip_address in container["networks"].items():
                networks_config[net_name] = {"ipv4_address": ip_address}

            depends_on = []
            # Infer depends_on from the chain order defined in config.json
            # Assumes a linear dependency where each container depends on the previous one.
            current_index = self.CONTAINERS.index(container)
            if current_index > 0:
                depends_on.append(self.CONTAINERS[current_index - 1]["name"])

            compose_data["services"][service_name] = {
                "build": {
                    "context": ".",
                    "dockerfile": container["dockerfile"]
                },
                "container_name": service_name,
                "hostname": service_name,
                "privileged": True,
                "volumes": [
                    # Mount container-specific config directory. Assumes directory name matches container name after 'chain-'
                    f"./src/containers/{service_name.replace('chain-', '')}:/vpp-config:ro",
                    "./src/configs:/vpp-common:ro",
                    "/tmp/vpp-logs:/var/log/vpp"
                ],
                "networks": networks_config,
                "cap_add": [
                    "NET_ADMIN",
                    "SYS_ADMIN",
                    "IPC_LOCK"
                ],
                "ulimits": {
                    "memlock": {"soft": -1, "hard": -1}
                },
                "depends_on": depends_on
            }
            # Add packet-captures volume for chain-gcp
            if service_name == "chain-gcp":
                compose_data["services"][service_name]["volumes"].append("/tmp/packet-captures:/tmp")

        compose_file_path = self.project_root / "docker-compose.yml"
        temp_compose_file_path = Path("/tmp") / "docker-compose.yml"

        try:
            # Attempt to remove existing docker-compose.yml with sudo
            if compose_file_path.exists():
                log_info(f"Attempting to remove existing {compose_file_path}...")
                subprocess.run([
                    "sudo", "rm", "-f", str(compose_file_path)
                ], capture_output=True, text=True, check=True)
                log_success(f"Successfully removed existing {compose_file_path}")

            with open(temp_compose_file_path, 'w') as f:
                yaml.dump(compose_data, f, sort_keys=False)
            log_success(f"docker-compose.yml generated at {temp_compose_file_path}")

            # Use sudo mv to move the file to the project root
            result = subprocess.run([
                "sudo", "mv", str(temp_compose_file_path), str(compose_file_path)
            ], capture_output=True, text=True, check=True)
            log_success(f"docker-compose.yml moved to {compose_file_path}")
            return True
        except subprocess.CalledProcessError as e:
            log_error(f"Failed to move docker-compose.yml: {e.stderr}")
            return False
        except Exception as e:
            log_error(f"Error generating/moving docker-compose.yml: {e}")
            return False

    def build_images(self):
        """Build container images"""
        try:
            log_info("Building VPP chain base image...")
            
            base_dockerfile_path = self.project_root / "src" / "containers" / "Dockerfile.base"
            
            # Build base image
            result = subprocess.run([
                "docker", "build", 
                "-t", "vpp-chain-base:latest",
                "-f", str(base_dockerfile_path),
                str(self.project_root)
            ], capture_output=True, text=True, check=True)
            
            log_success("VPP chain base image built successfully")

            # Build specialized container images
            # Assumes specialized Dockerfiles are named Dockerfile.<container_type> (e.g., Dockerfile.vxlan)
            # and located in src/containers/<container_type>/
            for container in self.CONTAINERS:
                container_dockerfile_path = self.project_root / "src" / "containers" / container["name"].replace("chain-", "") / f"Dockerfile.{container['name'].replace('chain-', '')}"
                
                if container_dockerfile_path.exists():
                    log_info(f"Building specialized image for {container['name']}...")
                    result = subprocess.run([
                        "docker", "build", 
                        "-t", f"{container['name']}:latest",
                        "-f", str(container_dockerfile_path),
                        str(self.project_root)
                    ], capture_output=True, text=True, check=True)
                    log_success(f"Specialized image for {container['name']} built successfully")
                else:
                    log_info(f"No specialized Dockerfile found for {container['name']}, using base image.")
            
            log_success("All container images built successfully")
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
            
            # Start containers using docker compose v2
            result = subprocess.run([
                "docker", "compose", "-f", str(compose_file),
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
            
            # Stop containers using docker compose v2
            subprocess.run([
                "docker", "compose", "-f", str(compose_file),
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
                
                # Quick status check - monitoring all containers
                for container in self.CONTAINERS:
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

            for container in self.CONTAINERS:
                try:
                    subprocess.run([
                        "docker", "image", "rm", f"{container['name']}:latest"
                    ], capture_output=True, text=True)
                except:
                    pass
            
            # System cleanup
            subprocess.run([
                "docker", "system", "prune", "-f"
            ], capture_output=True, text=True)
            
            log_success("Container images cleaned up")
            return True
            
        except Exception as e:
            log_error(f"Image cleanup failed: {e}")
            return False