"""
Container Management for VPP Multi-Container Chain

Handles Docker container lifecycle, VPP configuration, and debugging operations.
"""

import subprocess
import time
from pathlib import Path
import yaml # Used for docker-compose.yml generation (legacy support)
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
        for container_name, container in self.CONTAINERS.items():
            service_name = container_name
            networks_config = {}
            # Convert interfaces to networks config
            for interface in container["interfaces"]:
                net_name = interface["network"]
                ip_address = interface["ip"]["address"]
                networks_config[net_name] = {"ipv4_address": ip_address}

            depends_on = []
            # Define dependency chain order for new 3-container architecture
            chain_order = ["vxlan-processor", "security-processor", "destination"]
            if container_name in chain_order:
                current_index = chain_order.index(container_name)
                if current_index > 0:
                    depends_on.append(chain_order[current_index - 1])

            compose_data["services"][service_name] = {
                "build": {
                    "context": ".",
                    "dockerfile": container["dockerfile"]
                },
                "container_name": service_name,
                "hostname": service_name,
                "privileged": True,
                "volumes": [
                    # Mount container-specific config directory for new architecture
                    "./src/containers:/vpp-config:ro",
                    "/tmp/vpp-logs:/var/log/vpp",
                    "/tmp/packet-captures:/tmp"
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
            log_info("Building VPP 3-container chain images...")

            # Build specialized container images for new 3-container architecture
            for container_name, container in self.CONTAINERS.items():
                dockerfile_path = self.project_root / container["dockerfile"]
                
                if dockerfile_path.exists():
                    log_info(f"Building image for {container_name}...")
                    result = subprocess.run([
                        "docker", "build", 
                        "-t", f"{container_name}:latest",
                        "-f", str(dockerfile_path),
                        str(self.project_root)
                    ], capture_output=True, text=True, check=True)
                    log_success(f"Image for {container_name} built successfully")
                else:
                    log_error(f"Dockerfile not found: {dockerfile_path}")
                    return False
            
            log_success("All container images built successfully")
            return True
            
        except subprocess.CalledProcessError as e:
            log_error(f"Failed to build images: {e.stderr}")
            return False
        except Exception as e:
            log_error(f"Image build failed: {e}")
            return False
    
    def _run_single_container(self, container_name, container_info):
        """Helper to run a single container and apply its VPP config."""
        log_info(f"Starting {container_name}...")

        # Construct docker run command
        run_command = [
            "docker", "run", "-d",
            "--name", container_name,
            "-h", container_name,
            "--privileged"
        ]

        # Add environment variable with container config
        import json
        run_command.extend(["-e", f"VPP_CONFIG={json.dumps(container_info)}"])

        # Add capabilities
        for cap in ["NET_ADMIN", "SYS_ADMIN", "IPC_LOCK"]:
            run_command.extend(["--cap-add", cap])

        # Add ulimits
        run_command.extend(["--ulimit", "memlock=-1:-1"])

        # Add volumes
        run_command.extend([
            "-v", f"{self.project_root}/src/containers:/vpp-config:ro",
            "-v", "/tmp/vpp-logs:/var/log/vpp"
        ])
        if container_name == "destination":
            run_command.extend(["-v", "/tmp/packet-captures:/tmp"])

        # Add primary network and IP
        primary_interface = container_info["interfaces"][0]
        primary_network_name = primary_interface["network"]
        primary_ip_address = primary_interface["ip"]["address"]
        run_command.extend(["--network", primary_network_name, "--ip", primary_ip_address])

        # Add image name
        run_command.append(f"{container_name}:latest")

        # Execute docker run
        subprocess.run(run_command, capture_output=True, text=True, check=True)
        log_success(f"{container_name} started.")

        # Connect to secondary networks
        for interface in container_info["interfaces"][1:]:
            secondary_net_name = interface["network"]
            secondary_ip_address = interface["ip"]["address"]
            log_info(f"Connecting {container_name} to {secondary_net_name} with IP {secondary_ip_address}...")
            subprocess.run([
                "docker", "network", "connect",
                "--ip", secondary_ip_address,
                secondary_net_name,
                container_name
            ], capture_output=True, text=True, check=True)
            log_success(f"{container_name} connected to {secondary_net_name}.")

        # Start VPP and apply config
        log_info(f"Starting VPP and applying configuration for {container_name}...")
        subprocess.run([
            "docker", "exec", container_name, "bash", "-c",
            "/vpp-common/start-vpp.sh &"
        ], capture_output=True, text=True, check=True)
        time.sleep(10) # Give VPP some time to start
        subprocess.run([
            "docker", "exec", container_name, "bash", "-c",
            f"cd /vpp-config && ./{Path(container_info['config_script']).name}"
        ], capture_output=True, text=True, check=True)
        log_success(f"VPP configured for {container_name}.")

    def _stop_single_container(self, container_name):
        """Helper to stop and remove a single container."""
        log_info(f"Stopping and removing {container_name}...")
        subprocess.run(["docker", "rm", "-f", container_name], capture_output=True, text=True)
        log_success(f"{container_name} stopped and removed.")

    def start_containers(self):
        """Start all containers manually using docker run commands."""
        try:
            log_info("Starting container chain manually...")
            for container_name, container_info in sorted(self.CONTAINERS.items()):
                self._run_single_container(container_name, container_info)
            log_success("All containers started and configured successfully!")
            return True
        except subprocess.CalledProcessError as e:
            log_error(f"Failed to start or configure containers: {e.stderr}")
            return False
        except Exception as e:
            log_error(f"Container startup failed: {e}")
            return False

    def stop_containers(self):
        """Stop and remove all containers."""
        try:
            log_info("Stopping and removing container chain...")
            # Reverse the container order for stopping
            container_items = list(self.CONTAINERS.items())
            for container_name, container_info in reversed(container_items):
                self._stop_single_container(container_name)
            log_success("All containers stopped and removed.")
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
            
            for container_name, container in self.CONTAINERS.items():
                log_info(f"Configuring {container_name} ({container['description']})...")
                
                # Execute configuration script in container
                result = subprocess.run([
                    "docker", "exec", container_name,
                    "bash", "-c", f"cd /vpp-config && ./{Path(container['config_script']).name}"
                ], capture_output=True, text=True)
                
                if result.returncode != 0:
                    log_error(f"Configuration failed for {container_name}: {result.stderr}")
                    return False
                
                log_success(f"{container_name} configured successfully")
            
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
            for container_name, container in self.CONTAINERS.items():
                if container_name in running_containers:
                    log_success(f"Container {container_name} is running")
                else:
                    log_error(f"Container {container_name} is not running")
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
            for container_name, container in self.CONTAINERS.items():
                try:
                    result = subprocess.run([
                        "docker", "exec", container_name, 
                        "vppctl", "show", "version"
                    ], capture_output=True, text=True, timeout=10)
                    
                    if result.returncode == 0:
                        log_success(f"VPP responsive in {container_name}")
                    else:
                        log_error(f"VPP not responsive in {container_name}")
                        all_responsive = False
                        
                except subprocess.TimeoutExpired:
                    log_error(f"VPP timeout in {container_name}")
                    all_responsive = False
                except Exception as e:
                    log_error(f"VPP check failed for {container_name}: {e}")
                    all_responsive = False
            
            return all_responsive
            
        except Exception as e:
            log_error(f"VPP verification failed: {e}")
            return False
    
    def debug_container(self, container_name, command):
        """Execute a VPP command in a specific container for debugging"""
        try:
            # Validate container name
            valid_containers = list(self.CONTAINERS.keys())
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
            
            for container_name, container in self.CONTAINERS.items():
                print(f"\n📦 {container_name} ({container['description']})")
                
                # Check if running
                try:
                    result = subprocess.run([
                        "docker", "ps", "--filter", f"name={container_name}",
                        "--format", "{{.Status}}"
                    ], capture_output=True, text=True)
                    
                    if result.stdout.strip():
                        print(f"   Status: Running ({result.stdout.strip()})")
                        
                        # Get VPP interface stats
                        try:
                            vpp_result = subprocess.run([
                                "docker", "exec", container_name, 
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
                                print(f"   VPP: Not responsive")
                        except:
                            print(f"   VPP: Status unknown")
                            
                    else:
                        print(f"   Status: 🔴 Not running")
                        
                except Exception as e:
                    print(f"   Status: Error checking status")
            
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
                print(f"\nMonitoring... ({int(time.time() - start_time)}/{duration}s)")
                
                # Quick status check - monitoring all containers
                for container_name, container in self.CONTAINERS.items():
                    try:
                        result = subprocess.run([
                            "docker", "exec", container_name,
                            "vppctl", "show", "interface"
                        ], capture_output=True, text=True, timeout=5)
                        
                        if result.returncode == 0:
                            print(f"   {container_name}: Active")
                        else:
                            print(f"   {container_name}: Issue")
                    except:
                        print(f"   {container_name}: Timeout")
                
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

            for container_name, container in self.CONTAINERS.items():
                try:
                    subprocess.run([
                        "docker", "image", "rm", f"{container_name}:latest"
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